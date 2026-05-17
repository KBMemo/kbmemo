import { Decoration, WidgetType } from "@codemirror/view"
import { isTableBodyLine, isTableHeaderRow, isTableRowLine, TABLE_DELIM } from "./table_syntax"

class TableCaptionWidget extends WidgetType {
  constructor(label) {
    super()
    this.label = label
  }

  eq(other) {
    return other.label === this.label
  }

  toDOM() {
    const span = document.createElement("span")
    span.className = "cm-wysiwyg-table-caption"
    span.textContent = this.label
    span.setAttribute("aria-hidden", "true")
    return span
  }

  ignoreEvent() {
    return true
  }
}

export function cursorInTableBlock(state, block) {
  return state.selection.ranges.some((range) => {
    const lineNo = state.doc.lineAt(range.head).number
    return lineNo >= block.startLine && lineNo <= block.endLine
  })
}

function hideRangeForLine(text, lineNo, block) {
  const trimmed = text.trim()

  if (lineNo === block.titleLine) {
    const dot = text.indexOf(".")
    if (dot === -1) return null
    const titleText = text.slice(dot + 1).trim()
    return {
      from: dot,
      to: text.length,
      widget: new TableCaptionWidget(block.title || titleText)
    }
  }

  if (block.attrLines.includes(lineNo)) {
    const start = text.indexOf(trimmed)
    return { from: start, to: start + trimmed.length, widget: null }
  }

  if (TABLE_DELIM.test(trimmed) && (lineNo === block.openLine || lineNo === block.closeLine)) {
    const start = text.indexOf(trimmed)
    const widget = lineNo === block.openLine ? new TableCaptionWidget("Table") : null
    return { from: start, to: start + trimmed.length, widget }
  }

  return null
}

export function applyTableWysiwyg(specs, atomicRanges, line, text, lineNo, block) {
  const isTitleLine = lineNo === block.titleLine
  const isAttrLine = block.attrLines.includes(lineNo)
  const isBodyLine = isTableBodyLine(lineNo, block)
  const isRowLine = isBodyLine && isTableRowLine(text)
  const isHeaderRow = isRowLine && isTableHeaderRow(text)
  const hide = hideRangeForLine(text, lineNo, block)

  const lineClass = [
    isTitleLine ? "cm-wysiwyg-table-title-line" : "",
    isAttrLine ? "cm-wysiwyg-table-attr-line" : "",
    isBodyLine ? "cm-wysiwyg-table" : "",
    isBodyLine && lineNo === block.openLine ? "cm-wysiwyg-table-first cm-wysiwyg-table-open-line" : "",
    isBodyLine && lineNo === block.endLine ? "cm-wysiwyg-table-last" : "",
    isRowLine ? "cm-wysiwyg-table-row" : "",
    isHeaderRow ? "cm-wysiwyg-table-row-header" : "",
    isBodyLine && !isRowLine && lineNo !== block.openLine && lineNo !== block.closeLine
      ? "cm-wysiwyg-table-gap"
      : ""
  ]
    .filter(Boolean)
    .join(" ")

  if (lineClass) {
    pushSpec(specs, line.from, line.from, Decoration.line({ class: lineClass }), "line")
  }

  if (!hide || hide.to <= hide.from) return

  const hideFrom = line.from + hide.from
  const hideTo = line.from + hide.to
  const deco = hide.widget ? Decoration.replace({ widget: hide.widget }) : Decoration.replace({})
  pushSpec(specs, hideFrom, hideTo, deco, "replace")
  atomicRanges.push({ from: hideFrom, to: hideTo })
}

function pushSpec(specs, from, to, deco, kind) {
  specs.push({ from, to, deco, kind })
}
