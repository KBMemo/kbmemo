import { Decoration, WidgetType } from "@codemirror/view"
import {
  BLOCK_TITLE_LINE,
  FENCE_CLOSE,
  FENCE_OPEN,
  LISTING_DELIM,
  LITERAL_DELIM,
  SOURCE_ATTR_LINE
} from "./code_block_syntax"

class CodeBlockLabelWidget extends WidgetType {
  constructor(label) {
    super()
    this.label = label
  }

  eq(other) {
    return other.label === this.label
  }

  toDOM() {
    const span = document.createElement("span")
    span.className = "cm-wysiwyg-code-block-lang"
    span.textContent = this.label
    span.setAttribute("aria-hidden", "true")
    return span
  }

  ignoreEvent() {
    return true
  }
}

class CodeBlockTitleWidget extends WidgetType {
  constructor(title) {
    super()
    this.title = title
  }

  eq(other) {
    return other.title === this.title
  }

  toDOM() {
    const span = document.createElement("span")
    span.className = "cm-wysiwyg-code-block-title"
    span.textContent = this.title
    span.setAttribute("aria-hidden", "true")
    return span
  }

  ignoreEvent() {
    return true
  }
}

export function cursorInCodeBlock(state, block) {
  return state.selection.ranges.some((range) => {
    const lineNo = state.doc.lineAt(range.head).number
    return lineNo >= block.startLine && lineNo <= block.endLine
  })
}

function openDelimiterLabel(block) {
  if (block.kind === "fence") return block.language || "text"
  if (block.kind === "source" && block.language) return block.language
  if (block.kind === "listing") return "Listing"
  return "Literal"
}

function hideRangeForLine(text, lineNo, block) {
  if (block.kind === "fence") {
    if (lineNo === block.openLine) {
      const match = text.match(FENCE_OPEN)
      if (!match) return null
      return { from: 0, to: match[0].length, widget: new CodeBlockLabelWidget(openDelimiterLabel(block)) }
    }
    if (block.closeLine != null && lineNo === block.closeLine && FENCE_CLOSE.test(text)) {
      return { from: 0, to: text.length, widget: null }
    }
    return null
  }

  if (lineNo === block.titleLine) {
    const match = text.trim().match(BLOCK_TITLE_LINE)
    if (!match) return null
    const start = text.indexOf(match[0])
    return {
      from: start,
      to: start + match[0].length,
      widget: new CodeBlockTitleWidget(block.title)
    }
  }

  if (lineNo === block.attrLine) {
    const trimmed = text.trim()
    const match = trimmed.match(SOURCE_ATTR_LINE)
    if (!match) return null
    const start = text.indexOf(trimmed)
    return { from: start, to: start + trimmed.length, widget: null }
  }

  const trimmed = text.trim()
  if (lineNo === block.openLine && LISTING_DELIM.test(trimmed)) {
    const start = text.indexOf(trimmed)
    return {
      from: start,
      to: start + trimmed.length,
      widget: new CodeBlockLabelWidget(openDelimiterLabel(block))
    }
  }

  if (block.closeLine != null && lineNo === block.closeLine && LISTING_DELIM.test(trimmed)) {
    const start = text.indexOf(trimmed)
    return { from: start, to: start + trimmed.length, widget: null }
  }

  if (block.kind === "literal") {
    if (lineNo === block.openLine || (block.closeLine != null && lineNo === block.closeLine)) {
      if (LITERAL_DELIM.test(trimmed)) {
        const start = text.indexOf(trimmed)
        const widget =
          lineNo === block.openLine ? new CodeBlockLabelWidget("Literal") : null
        return { from: start, to: start + trimmed.length, widget }
      }
    }
  }

  return null
}

function isCodeBlockBodyLine(lineNo, block) {
  return lineNo >= block.openLine && lineNo <= block.endLine
}

export function applyCodeBlockWysiwyg(specs, atomicRanges, line, text, lineNo, block) {
  const isOpenLine = lineNo === block.openLine
  const isAttrLine = lineNo === block.attrLine
  const isTitleLine = lineNo === block.titleLine
  const isBodyLine = isCodeBlockBodyLine(lineNo, block)
  const hide = hideRangeForLine(text, lineNo, block)
  const showsLangLabel = hide?.widget instanceof CodeBlockLabelWidget

  const lineClass = [
    isTitleLine ? "cm-wysiwyg-code-block-title-line" : "",
    isAttrLine ? "cm-wysiwyg-code-block-attr-line" : "",
    isBodyLine ? "cm-wysiwyg-code-block" : "",
    isBodyLine ? `cm-wysiwyg-code-block-${block.kind}` : "",
    isBodyLine && lineNo === block.openLine ? "cm-wysiwyg-code-block-first" : "",
    isBodyLine && lineNo === block.endLine ? "cm-wysiwyg-code-block-last" : "",
    isOpenLine && showsLangLabel ? "cm-wysiwyg-code-block-open-line" : ""
  ]
    .filter(Boolean)
    .join(" ")
  if (lineClass) {
    pushSpec(specs, line.from, line.from, Decoration.line({ class: lineClass }), "line")
  }

  if (!hide || hide.to <= hide.from) return

  const hideFrom = line.from + hide.from
  const hideTo = line.from + hide.to
  const deco = hide.widget
    ? Decoration.replace({ widget: hide.widget })
    : Decoration.replace({})
  pushSpec(specs, hideFrom, hideTo, deco, "replace")
  atomicRanges.push({ from: hideFrom, to: hideTo })
}

function pushSpec(specs, from, to, deco, kind) {
  specs.push({ from, to, deco, kind })
}
