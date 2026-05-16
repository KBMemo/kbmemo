import { RangeSet, RangeSetBuilder } from "@codemirror/state"
import { Decoration, EditorView, ViewPlugin } from "@codemirror/view"

const HEADING_LINE = /^(={2,6})(\s+)(.+)$/
const DOC_TITLE_LINE = /^=(?!=)(\s*)(.*)$/
const BOLD_INLINE = /\*([^*\s][^*]*?)\*/g
const ITALIC_INLINE = /_([^_\s][^_]*?)_/g
const WIKI_LINK = /\[\[[^\]]+\]\]/g
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

function wikiLinkRanges(text, lineFrom) {
  const ranges = []
  for (const match of text.matchAll(WIKI_LINK)) {
    ranges.push([lineFrom + match.index, lineFrom + match.index + match[0].length])
  }
  return ranges
}

function overlapsWiki(pos, end, wikiRanges) {
  return wikiRanges.some(([from, to]) => pos < to && end > from)
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
  const wikiRanges = wikiLinkRanges(text, lineFrom)
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
      if (overlapsWiki(fullFrom, fullTo, wikiRanges)) continue
      if (overlapsOccupied(fullFrom, fullTo)) continue
      if (editingActive && selectionTouches(state, fullFrom, fullTo)) continue

      pushSpec(specs, fullFrom, contentFrom, Decoration.replace({}), "replace")
      pushSpec(specs, contentTo, fullTo, Decoration.replace({}), "replace")
      pushSpec(specs, contentFrom, contentTo, Decoration.mark({ class: markClass }), "mark")
      atomicRanges.push({ from: fullFrom, to: contentFrom }, { from: contentTo, to: fullTo })
      markOccupied(fullFrom, fullTo)
    }
  }

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
 * 対象: 1行目ドキュメントタイトル（= Title / プレーン1行目）、見出し（==…）、*bold*、_italic_
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
