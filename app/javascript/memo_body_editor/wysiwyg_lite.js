import { RangeSet } from "@codemirror/state"
import { Decoration, EditorView, ViewPlugin, WidgetType } from "@codemirror/view"
import { admonitionBlockByLine, scanAdmonitionBlocks } from "./admonition_syntax"
import { applyAdmonitionWysiwyg, cursorInAdmonitionBlock } from "./admonition_wysiwyg"
import { codeBlockByLine, isFenceDelimiterLine, scanCodeBlocks } from "./code_block_syntax"
import { applyCodeBlockWysiwyg, cursorInCodeBlock } from "./code_block_wysiwyg"
import { imageExclusionRanges } from "./image_syntax"
import { linkExclusionRanges } from "./wiki_link_wysiwyg"
import { orderedListIndex, parseListLine } from "./list_syntax"
import { scanTableBlocks, tableBlockByLine } from "./table_syntax"
import {
  getViewportLineRange,
  shouldDecorateEditorBlock,
  shouldDecorateEditorLine
} from "./viewport_lazy"

const HEADING_LINE = /^(={2,6})(\s+)(.+)$/
const DOC_TITLE_LINE = /^=(?!=)(\s*)(.*)$/
const BOLD_INLINE = /\*([^*\s][^*]*?)\*/g
const ITALIC_INLINE = /_([^_\s][^_]*?)_/g
const MONO_DBL_BACKTICK = /``([^`\s][^`]*?)``/g
const MONO_BACKTICK = /`([^`\s][^`]*?)`/g
const MONO_DBL_PLUS = /\+\+([^+\s][^+]*?)\+\+/g
const MONO_PLUS = /\+([^+\s][^+]*?)\+/g

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
  if (lineNo !== 1 || !text.trim() || isFenceDelimiterLine(text)) return null

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

const LOWER_ROMAN = ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"]

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

function overlapsExcludedRange(pos, end, ranges) {
  return ranges.some(([from, to]) => pos < to && end > from)
}

function pushSpec(specs, from, to, deco, kind) {
  specs.push({ from, to, deco, kind })
}

function decorateInline(specs, atomicRanges, line, text, lineFrom, state, editingActive) {
  const linkRanges = linkExclusionRanges(text, lineFrom)
  const imageRanges = imageExclusionRanges(text, lineFrom)
  const excludeRanges = linkRanges.concat(imageRanges)
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
      if (overlapsExcludedRange(fullFrom, fullTo, excludeRanges)) continue
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
  const codeBlocks = scanCodeBlocks(state.doc)
  const codeByLine = codeBlockByLine(codeBlocks)
  const tableBlocks = scanTableBlocks(state.doc, (n) => codeByLine.has(n))
  const tableByLine = tableBlockByLine(tableBlocks)
  const skipBlockLine = (n) => codeByLine.has(n) || tableByLine.has(n)
  const admonitionBlocks = scanAdmonitionBlocks(state.doc, skipBlockLine)
  const admonitionByLine = admonitionBlockByLine(admonitionBlocks)
  const viewportRange = getViewportLineRange(state)

  for (let lineNo = 1; lineNo <= state.doc.lines; lineNo++) {
    const line = state.doc.line(lineNo)
    const text = line.text

    const codeBlock = codeByLine.get(lineNo)
    const editingCode = codeBlock && editingActive && cursorInCodeBlock(state, codeBlock)

    if (codeBlock && !editingCode) {
      if (shouldDecorateEditorBlock(view, codeBlock.startLine, codeBlock.endLine, viewportRange)) {
        applyCodeBlockWysiwyg(specs, atomicRanges, line, text, lineNo, codeBlock)
      }
      continue
    }
    if (codeBlock) continue

    if (tableByLine.has(lineNo)) continue

    if (!shouldDecorateEditorLine(view, lineNo, viewportRange)) continue

    const onLine = editingActive && cursorOnLine(state, line)
    const admonition = admonitionByLine.get(lineNo)
    const editingAdmonition =
      admonition && editingActive && cursorInAdmonitionBlock(state, admonition)

    if (!onLine && !editingAdmonition) {
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

      if (admonition) {
        applyAdmonitionWysiwyg(specs, atomicRanges, line, text, lineNo, admonition)
      }
    }

    decorateInline(specs, atomicRanges, line, text, line.from, state, editingActive)
  }

  const decorations = Decoration.set(
    specs.map((spec) => spec.deco.range(spec.from, spec.to)),
    true
  )

  const atomic =
    atomicRanges.length > 0
      ? RangeSet.of(
          atomicRanges.map((r) => Decoration.replace({}).range(r.from, r.to)),
          true
        )
      : RangeSet.empty

  return { decorations, atomicRanges: atomic }
}

/**
 * Phase 4: フォーカス時、カーソル行の見出しのみ生 AsciiDoc。インラインは選択範囲内のみ生表示。
 * 非フォーカス時は全文プレビュー風。
 * 対象: 1行目ドキュメントタイトル（= Title / プレーン1行目）、見出し（==…）、
 * リスト行（Phase 5a）、admonition（Phase 5b）、コードブロック（Phase 5c）、
 * テーブル（Phase 5d は table_wysiwyg_field）、
 * *bold*、_italic_、`` ` `` / `` + `` モノスペース
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
