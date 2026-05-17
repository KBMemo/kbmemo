import { Decoration, WidgetType } from "@codemirror/view"
import { codeBlockByLine, scanCodeBlocks } from "./code_block_syntax"
import {
  groupTableLogicalRows,
  isTableBodyLine,
  isTableRowLine,
  scanTableBlocks,
  selectionInTableBlock,
  TABLE_DELIM
} from "./table_syntax"
import { activateTableBlock } from "./table_wysiwyg_effects"

function bindTableWidgetActivate(el, view, blockStartLine, editLineNo) {
  if (!view) return
  el.addEventListener("mousedown", (event) => {
    if (event.button !== 0) return
    event.preventDefault()
    event.stopPropagation()
    activateTableBlock(view, blockStartLine, editLineNo)
  })
}

class TableCaptionWidget extends WidgetType {
  constructor(label, blockStartLine, editLineNo) {
    super()
    this.label = label
    this.blockStartLine = blockStartLine
    this.editLineNo = editLineNo
  }

  eq(other) {
    return (
      other.label === this.label &&
      other.blockStartLine === this.blockStartLine &&
      other.editLineNo === this.editLineNo
    )
  }

  toDOM(view) {
    const span = document.createElement("span")
    span.className = "cm-wysiwyg-table-caption"
    span.textContent = this.label
    span.setAttribute("aria-hidden", "true")
    bindTableWidgetActivate(span, view, this.blockStartLine, this.editLineNo)
    return span
  }

  ignoreEvent() {
    return false
  }
}

export class TableRowWidget extends WidgetType {
  constructor(cells, isHeader, colsFr, lineClass, blockStartLine, editLineNo) {
    super()
    this.cells = cells
    this.isHeader = isHeader
    this.colsFr = colsFr
    this.lineClass = lineClass
    this.blockStartLine = blockStartLine
    this.editLineNo = editLineNo
  }

  eq(other) {
    return (
      other.isHeader === this.isHeader &&
      other.lineClass === this.lineClass &&
      other.blockStartLine === this.blockStartLine &&
      other.editLineNo === this.editLineNo &&
      other.cells.length === this.cells.length &&
      other.cells.every((cell, index) => cell === this.cells[index]) &&
      JSON.stringify(other.colsFr) === JSON.stringify(this.colsFr)
    )
  }

  toDOM(view) {
    const row = document.createElement("div")
    row.className = ["cm-wysiwyg-table-grid-row", this.lineClass].filter(Boolean).join(" ")
    if (this.isHeader) row.classList.add("cm-wysiwyg-table-grid-row--header")

    if (this.colsFr?.length) {
      row.style.gridTemplateColumns = this.colsFr.join(" ")
    } else {
      row.style.gridTemplateColumns = `repeat(${this.cells.length}, minmax(0, 1fr))`
    }

    for (const cell of this.cells) {
      const cellEl = document.createElement("span")
      cellEl.className = "cm-wysiwyg-table-grid-cell"
      cellEl.textContent = cell
      row.appendChild(cellEl)
    }

    bindTableWidgetActivate(row, view, this.blockStartLine, this.editLineNo)
    return row
  }

  ignoreEvent() {
    return false
  }

  get estimatedHeight() {
    return 32
  }
}

/** @deprecated selectionInTableBlock を使用 */
export function cursorInTableBlock(state, block) {
  return selectionInTableBlock(state, block)
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
      widget: new TableCaptionWidget(block.title || titleText, block.startLine, lineNo)
    }
  }

  if (block.attrLines.includes(lineNo)) {
    const start = text.indexOf(trimmed)
    return { from: start, to: start + trimmed.length, widget: null }
  }

  if (TABLE_DELIM.test(trimmed) && (lineNo === block.openLine || lineNo === block.closeLine)) {
    const start = text.indexOf(trimmed)
    const widget =
      lineNo === block.openLine ? new TableCaptionWidget("Table", block.startLine, lineNo) : null
    return { from: start, to: start + trimmed.length, widget }
  }

  return null
}

function lineClassForTableLine(lineNo, block, text) {
  const isTitleLine = lineNo === block.titleLine
  const isAttrLine = block.attrLines.includes(lineNo)
  const isBodyLine = isTableBodyLine(lineNo, block)
  const isRowLine = isBodyLine && isTableRowLine(text)

  return [
    isTitleLine ? "cm-wysiwyg-table-title-line" : "",
    isAttrLine ? "cm-wysiwyg-table-attr-line" : "",
    isBodyLine ? "cm-wysiwyg-table" : "",
    isBodyLine && lineNo === block.openLine ? "cm-wysiwyg-table-first cm-wysiwyg-table-open-line" : "",
    isBodyLine && lineNo === block.endLine ? "cm-wysiwyg-table-last" : "",
    isRowLine ? "cm-wysiwyg-table-row" : "",
    isBodyLine && !isRowLine && lineNo !== block.openLine && lineNo !== block.closeLine
      ? "cm-wysiwyg-table-gap"
      : ""
  ]
    .filter(Boolean)
    .join(" ")
}

/**
 * StateField 用: 表ブロックの block replace + 周辺行の line/replace 装飾。
 * 選択がブロック内にある間は装飾しない（ソース編集）。
 */
export function buildTablePreviewDecorations(state, activeTableStartLine = null) {
  const decoRanges = []
  const coveredByLogicalRow = new Set()

  const codeBlocks = scanCodeBlocks(state.doc)
  const codeByLine = codeBlockByLine(codeBlocks)
  const blocks = scanTableBlocks(state.doc, (n) => codeByLine.has(n))

  for (const block of blocks) {
    if (activeTableStartLine != null && block.startLine === activeTableStartLine) continue

    const logicalRows = groupTableLogicalRows(state.doc, block)

    for (const row of logicalRows) {
      if (row.kind === "row") {
        for (let n = row.startLine; n <= row.endLine; n++) coveredByLogicalRow.add(n)
        const from = state.doc.line(row.startLine).from
        const to = state.doc.line(row.endLine).to
        const lineClass = [
          "cm-wysiwyg-table-row",
          row.isHeader ? "cm-wysiwyg-table-row-header" : ""
        ]
          .filter(Boolean)
          .join(" ")

        decoRanges.push(
          Decoration.replace({
            widget: new TableRowWidget(
              row.cells,
              row.isHeader,
              block.colsFr,
              lineClass,
              block.startLine,
              row.startLine
            ),
            block: true,
            inclusive: true
          }).range(from, to)
        )
        continue
      }

      const line = state.doc.line(row.lineNo)
      coveredByLogicalRow.add(row.lineNo)
      decoRanges.push(Decoration.line({ class: "cm-wysiwyg-table-gap" }).range(line.from))
    }

    for (let lineNo = block.startLine; lineNo <= block.endLine; lineNo++) {
      if (coveredByLogicalRow.has(lineNo)) continue

      const line = state.doc.line(lineNo)
      const text = line.text
      const lineClass = lineClassForTableLine(lineNo, block, text)

      if (lineClass) {
        decoRanges.push(Decoration.line({ class: lineClass }).range(line.from))
      }

      const hide = hideRangeForLine(text, lineNo, block)
      if (!hide || hide.to <= hide.from) continue

      const hideFrom = line.from + hide.from
      const hideTo = line.from + hide.to
      const deco = hide.widget
        ? Decoration.replace({ widget: hide.widget })
        : Decoration.replace({})
      decoRanges.push(deco.range(hideFrom, hideTo))
    }
  }

  return {
    decorations:
      decoRanges.length > 0 ? Decoration.set(decoRanges, true) : Decoration.none
  }
}
