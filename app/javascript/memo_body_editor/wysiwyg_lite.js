import { RangeSet, RangeSetBuilder } from "@codemirror/state"
import { Decoration, EditorView, ViewPlugin, WidgetType } from "@codemirror/view"
import { linkExclusionRanges } from "./wiki_link_wysiwyg"

const HEADING_LINE = /^(={2,6})(\s+)(.+)$/
const DOC_TITLE_LINE = /^=(?!=)(\s*)(.*)$/
const BOLD_INLINE = /\*([^*\s][^*]*?)\*/g
const ITALIC_INLINE = /_([^_\s][^_]*?)_/g
const MONO_DBL_BACKTICK = /``([^`\s][^`]*?)``/g
const MONO_BACKTICK = /`([^`\s][^`]*?)`/g
const MONO_DBL_PLUS = /\+\+([^+\s][^+]*?)\+\+/g
const MONO_PLUS = /\+([^+\s][^+]*?)\+/g
// codemirror-asciidoc listStart と同型（行頭マーカー + 空白）
const LIST_LINE =
  /^(\s*)((?:\d+\.|[a-zA-Z]\.|[ixvmIXVM]+\)|\*{1,5}|-|\.{1,5}))(\s+)(.*)$/

const FENCE_LINE = /^```/

const KIND_ORDER = { line: 0, replace: 1, mark: 2 }

/** 選択範囲が [from, to) と重なるか */
function selectionTouches(state, from, to) {
  return state.selection.ranges.some((range) => {
    const start = Math.min(range.anchor, range.head)
    const end = Math.max(range.anchor, range.head)
    return start < to && end > from
  })
}

function cursorOnLine(state, line) {
  return state.selection.ranges.some((range) => state.doc.lineAt(range.head).number === line.number)
}

/** 1行目の AsciiDoc ドキュメントタイトル（= Title）またはプレーン1行目 */
function parseDocumentTitleLine(lineNo, text) {
  if (lineNo !== 1 || !text.trim() || FENCE_LINE.test(text)) return null

  const marked = text.match(DOC_TITLE_LINE)
  if (marked) {
    return {
      markerLength: 1 + marked[1].length,
      lineClass: "cm-wysiwyg-heading cm-wysiwyg-doc-title"
    }
  }

  if (!HEADING_LINE.test(text)) {
    return { markerLength: 0, lineClass: "cm-wysiwyg-heading cm-wysiwyg-doc-title" }
  }

  return null
}

function applyHeadingWysiwyg(specs, atomicRanges, line, markerEnd, lineClass) {
  pushSpec(specs, line.from, line.from, Decoration.line({ class: lineClass }), "line")
  if (markerEnd > line.from) {
    pushSpec(specs, line.from, markerEnd, Decoration.replace({}), "replace")
    atomicRanges.push({ from: line.from, to: markerEnd })
  }
}

function listKind(marker) {
  if (/^\*+$/.test(marker) || marker === "-") return "bullet"
  // `.` / `..` / `1.` 等は有序リスト（番号省略の `. ` 含む）
  return "ordered"
}

function listLevel(indent, marker) {
  const indentCols = indent.replace(/\t/g, "  ").length
  const indentLevel = Math.floor(indentCols / 2)
  if (/^\*+$/.test(marker)) return Math.min(5, indentLevel + marker.length)
  if (/^\.+$/.test(marker)) return Math.min(5, indentLevel + marker.length)
  return Math.min(5, indentLevel + 1)
}

function parseListLine(text) {
  const match = text.match(LIST_LINE)
  if (!match) return null

  const indent = match[1]
  const marker = match[2]
  const space = match[3]
  const markerEndInLine = indent.length + marker.length + space.length
  const kind = listKind(marker)
  const level = listLevel(indent, marker)

  return {
    indentLength: indent.length,
    markerEndInLine,
    kind,
    marker,
    level,
    lineClass: `cm-wysiwyg-list cm-wysiwyg-list-${kind} cm-wysiwyg-list-level-${level}`
  }
}

const LOWER_ROMAN = ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"]

/** 同じインデント・同じマーカー形式の連続有序行の序数（1 始まり） */
function orderedListIndex(doc, lineNo, indentLength, marker) {
  let index = 1
  for (let n = lineNo - 1; n >= 1; n--) {
    const prev = parseListLine(doc.line(n).text)
    if (!prev || prev.kind !== "ordered" || prev.indentLength !== indentLength) break
    if (prev.marker !== marker) break
    index++
  }
  return index
}

function lowerAlphaMarker(index) {
  if (index < 1 || index > 26) return `${index}.`
  return `${String.fromCharCode(96 + index)}.`
}

function upperAlphaMarker(index) {
  if (index < 1 || index > 26) return `${index}.`
  return `${String.fromCharCode(64 + index)}.`
}

function romanMarker(index, upper = false) {
  const base = index > 0 && index < LOWER_ROMAN.length ? LOWER_ROMAN[index] : String(index)
  return upper ? base.toUpperCase() : base
}

/** `.` → 1.、`..` → a.、`...` → i. …（Asciidoctor の dot 省略記法） */
function implicitOrderedMarkerLabel(index, marker) {
  const dots = marker.length
  if (dots === 1) return `${index}.`
  if (dots === 2) return lowerAlphaMarker(index)
  if (dots === 3) return `${romanMarker(index)}.`
  if (dots === 4) return upperAlphaMarker(index)
  return `${romanMarker(index, true)}.`
}

function listMarkerDisplay(doc, lineNo, parsed) {
  const { kind, marker, indentLength } = parsed
  if (kind === "ordered") {
    if (/^\d+\.$/.test(marker) || /^\.+$/.test(marker)) {
      const index = orderedListIndex(doc, lineNo, indentLength, marker)
      if (/^\.+$/.test(marker)) return implicitOrderedMarkerLabel(index, marker)
      return `${index}.`
    }
    return marker
  }
  if (marker === "-") return "•"
  if (marker.length <= 1) return "•"
  if (marker.length === 2) return "◦"
  return "▪"
}

class ListMarkerWidget extends WidgetType {
  constructor(label, kind, level) {
    super()
    this.label = label
    this.kind = kind
    this.level = level
  }

  eq(other) {
    return (
      other.label === this.label && other.kind === this.kind && other.level === this.level
    )
  }

  toDOM() {
    const span = document.createElement("span")
    span.className = `cm-wysiwyg-list-marker cm-wysiwyg-list-marker--${this.kind} cm-wysiwyg-list-marker--level-${this.level}`
    span.setAttribute("aria-hidden", "true")
    span.textContent = this.label
    return span
  }

  ignoreEvent() {
    return true
  }
}

function applyListWysiwyg(specs, atomicRanges, line, text, doc) {
  const parsed = parseListLine(text)
  if (!parsed) return false

  const hideStart = line.from + parsed.indentLength
  const hideEnd = line.from + parsed.markerEndInLine
  const markerLabel = listMarkerDisplay(doc, line.number, parsed)

  pushSpec(specs, line.from, line.from, Decoration.line({ class: parsed.lineClass }), "line")
  if (hideEnd > hideStart) {
    pushSpec(
      specs,
      hideStart,
      hideEnd,
      Decoration.replace({
        widget: new ListMarkerWidget(markerLabel, parsed.kind, parsed.level)
      }),
      "replace"
    )
    atomicRanges.push({ from: hideStart, to: hideEnd })
  }
  return true
}

function overlapsLinkRange(pos, end, linkRanges) {
  return linkRanges.some(([from, to]) => pos < to && end > from)
}

function pushSpec(specs, from, to, deco, kind) {
  specs.push({ from, to, deco, kind })
}

function sortSpecs(specs) {
  specs.sort((a, b) => {
    if (a.from !== b.from) return a.from - b.from
    if (a.to !== b.to) return a.to - b.to
    return KIND_ORDER[a.kind] - KIND_ORDER[b.kind]
  })
}

function decorateInline(specs, atomicRanges, line, text, lineFrom, state, editingActive) {
  const linkRanges = linkExclusionRanges(text, lineFrom)
  const occupied = []

  const overlapsOccupied = (from, to) =>
    occupied.some((span) => from < span.to && to > span.from)

  const markOccupied = (from, to) => {
    occupied.push({ from, to })
  }

  const apply = (re, markClass, delimLen) => {
    for (const match of text.matchAll(re)) {
      const fullFrom = lineFrom + match.index
      const fullTo = fullFrom + match[0].length
      const contentFrom = fullFrom + delimLen
      const contentTo = fullTo - delimLen

      if (contentFrom >= contentTo) continue
      if (overlapsLinkRange(fullFrom, fullTo, linkRanges)) continue
      if (overlapsOccupied(fullFrom, fullTo)) continue
      if (editingActive && selectionTouches(state, fullFrom, fullTo)) continue

      pushSpec(specs, fullFrom, contentFrom, Decoration.replace({}), "replace")
      pushSpec(specs, contentTo, fullTo, Decoration.replace({}), "replace")
      pushSpec(specs, contentFrom, contentTo, Decoration.mark({ class: markClass }), "mark")
      atomicRanges.push({ from: fullFrom, to: contentFrom }, { from: contentTo, to: fullTo })
      markOccupied(fullFrom, fullTo)
    }
  }

  apply(MONO_DBL_BACKTICK, "cm-wysiwyg-monospace", 2)
  apply(MONO_DBL_PLUS, "cm-wysiwyg-monospace", 2)
  apply(MONO_BACKTICK, "cm-wysiwyg-monospace", 1)
  apply(MONO_PLUS, "cm-wysiwyg-monospace", 1)
  apply(BOLD_INLINE, "cm-wysiwyg-bold", 1)
  apply(ITALIC_INLINE, "cm-wysiwyg-italic", 1)
}

function buildWysiwygDecorations(view) {
  const specs = []
  const atomicRanges = []
  const { state } = view
  const editingActive = view.hasFocus
  let inFenced = false

  for (let lineNo = 1; lineNo <= state.doc.lines; lineNo++) {
    const line = state.doc.line(lineNo)
    const text = line.text

    if (FENCE_LINE.test(text)) {
      inFenced = !inFenced
      continue
    }
    if (inFenced) continue

    const onLine = editingActive && cursorOnLine(state, line)

    if (!onLine) {
      const docTitle = parseDocumentTitleLine(lineNo, text)
      if (docTitle) {
        const markerEnd =
          docTitle.markerLength > 0 ? line.from + docTitle.markerLength : line.from
        applyHeadingWysiwyg(specs, atomicRanges, line, markerEnd, docTitle.lineClass)
        continue
      }

      const heading = text.match(HEADING_LINE)
      if (heading) {
        const markerEnd = line.from + heading[1].length + heading[2].length
        const lineClass = `cm-wysiwyg-heading cm-wysiwyg-heading-${heading[1].length}`
        applyHeadingWysiwyg(specs, atomicRanges, line, markerEnd, lineClass)
        continue
      }

      if (applyListWysiwyg(specs, atomicRanges, line, text, state.doc)) {
        continue
      }
    }

    decorateInline(specs, atomicRanges, line, text, line.from, state, editingActive)
  }

  sortSpecs(specs)

  const builder = new RangeSetBuilder()
  for (const spec of specs) {
    builder.add(spec.from, spec.to, spec.deco)
  }

  atomicRanges.sort((a, b) => a.from - b.from || a.to - b.to)

  const atomic =
    atomicRanges.length > 0
      ? RangeSet.of(atomicRanges.map((r) => Decoration.replace({}).range(r.from, r.to)))
      : RangeSet.empty

  return {
    decorations: builder.finish(),
    atomicRanges: atomic
  }
}

/**
 * Phase 4: フォーカス時、カーソル行の見出しのみ生 AsciiDoc。インラインは選択範囲内のみ生表示。
 * 非フォーカス時は全文プレビュー風。
 * 対象: 1行目ドキュメントタイトル（= Title / プレーン1行目）、見出し（==…）、
 * リスト行（Phase 5a）、*bold*、_italic_、`` ` `` / `` + `` モノスペース
 */
export function wysiwygLiteExtension() {
  const plugin = ViewPlugin.fromClass(
    class {
      constructor(view) {
        const built = buildWysiwygDecorations(view)
        this.decorations = built.decorations
        this.atomicRanges = built.atomicRanges
      }

      update(update) {
        if (
          update.docChanged ||
          update.selectionSet ||
          update.viewportChanged ||
          update.focusChanged
        ) {
          const built = buildWysiwygDecorations(update.view)
          this.decorations = built.decorations
          this.atomicRanges = built.atomicRanges
        }
      }
    },
    {
      decorations: (v) => v.decorations,
      provide: (plugin) =>
        EditorView.atomicRanges.of((view) => view.plugin(plugin)?.atomicRanges ?? RangeSet.empty)
    }
  )

  return plugin
}
