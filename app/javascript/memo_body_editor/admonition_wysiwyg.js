import { Decoration, WidgetType } from "@codemirror/view"
import { parseAdmonitionLabelLine } from "./admonition_syntax"

class AdmonitionLabelWidget extends WidgetType {
  constructor(kind) {
    super()
    this.kind = kind
  }

  eq(other) {
    return other.kind === this.kind
  }

  toDOM() {
    const icon = document.createElement("i")
    icon.className = `fa icon-${this.kind} cm-wysiwyg-admonition-icon`
    icon.setAttribute("aria-hidden", "true")
    return icon
  }

  ignoreEvent() {
    return true
  }
}

export function cursorInAdmonitionBlock(state, block) {
  return state.selection.ranges.some((range) => {
    const lineNo = state.doc.lineAt(range.head).number
    return lineNo >= block.startLine && lineNo <= block.endLine
  })
}

export function applyAdmonitionWysiwyg(specs, atomicRanges, line, text, lineNo, block) {
  const isLabelLine = lineNo === block.startLine
  const lineClass = [
    "cm-wysiwyg-admonition",
    `cm-wysiwyg-admonition-${block.kind}`,
    isLabelLine ? "cm-wysiwyg-admonition-label-line" : "cm-wysiwyg-admonition-body-line"
  ].join(" ")

  pushSpec(specs, line.from, line.from, Decoration.line({ class: lineClass }), "line")

  if (!isLabelLine) return

  const parsed = parseAdmonitionLabelLine(text)
  if (!parsed) return

  const hideEnd = line.from + parsed.labelLength
  if (hideEnd > line.from) {
    pushSpec(
      specs,
      line.from,
      hideEnd,
      Decoration.replace({ widget: new AdmonitionLabelWidget(block.kind) }),
      "replace"
    )
    atomicRanges.push({ from: line.from, to: hideEnd })
  }
}

function pushSpec(specs, from, to, deco, kind) {
  specs.push({ from, to, deco, kind })
}
