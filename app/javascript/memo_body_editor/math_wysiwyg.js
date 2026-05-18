import { RangeSet, StateField } from "@codemirror/state"
import { Decoration, EditorView, ViewPlugin, WidgetType } from "@codemirror/view"
import katex from "katex"
import { codeBlockByLine, scanCodeBlocks } from "./code_block_syntax"
import {
  scanInlineMathMacrosOnLine,
  scanStemBlocks,
  scanStemDraftLineSet,
  selectionHeadInStemBlock,
  stemBlockAtCoords,
  stemBlockAtLine,
  isStemPreambleLine,
  stemBlockForArrowKey,
  stemFirstEditLine
} from "./math_syntax"
import { activateStemBlock, setStemActiveBlock } from "./math_wysiwyg_effects"
import { scanTableBlocks, tableBlockByLine } from "./table_syntax"
import {
  blockInViewportRange,
  getViewportLineRange,
  setViewportLineRange,
  shouldDecorateEditorLine
} from "./viewport_lazy"

export { setStemActiveBlock, activateStemBlock } from "./math_wysiwyg_effects"

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

function skipLinesForMath(state) {
  const codeBlocks = scanCodeBlocks(state.doc)
  const codeByLine = codeBlockByLine(codeBlocks)
  const tableBlocks = scanTableBlocks(state.doc, (n) => codeByLine.has(n))
  const tableByLine = tableBlockByLine(tableBlocks)
  return (n) => codeByLine.has(n) || tableByLine.has(n)
}

class MathPreviewWidget extends WidgetType {
  constructor({ latex, displayMode, blockStartLine = null, editLineNo = null, title = null }) {
    super()
    this.latex = latex
    this.displayMode = displayMode
    this.blockStartLine = blockStartLine
    this.editLineNo = editLineNo
    this.title = title
  }

  eq(other) {
    return (
      other.latex === this.latex &&
      other.displayMode === this.displayMode &&
      other.blockStartLine === this.blockStartLine &&
      other.editLineNo === this.editLineNo &&
      other.title === this.title
    )
  }

  toDOM(view) {
    const latex = this.latex ?? ""

    if (!this.displayMode) {
      const el = document.createElement("span")
      el.className = "cm-wysiwyg-math cm-wysiwyg-math--inline"
      this.renderLatex(el, latex, false)
      return el
    }

    const fig = document.createElement("figure")
    fig.className = "cm-wysiwyg-math cm-wysiwyg-math--block cm-wysiwyg-math--clickable"
    fig.addEventListener("mousedown", (event) => {
      if (event.button !== 0) return
      event.preventDefault()
      event.stopPropagation()
      activateStemBlock(view, this.blockStartLine, this.editLineNo)
    })

    if (this.title) {
      const titleEl = document.createElement("p")
      titleEl.className = "cm-wysiwyg-math-title"
      titleEl.textContent = this.title
      fig.appendChild(titleEl)
    }

    const body = document.createElement("div")
    body.className = "cm-wysiwyg-math-body"
    this.renderLatex(body, latex, true)
    fig.appendChild(body)
    return fig
  }

  renderLatex(el, latex, displayMode) {
    if (!latex.trim()) {
      el.textContent = "（空の数式）"
      el.classList.add("cm-wysiwyg-math-empty")
      return
    }
    try {
      katex.render(latex, el, {
        throwOnError: false,
        displayMode,
        strict: "ignore"
      })
    } catch {
      el.textContent = latex
      el.classList.add("cm-wysiwyg-math-error")
    }
  }

  ignoreEvent(event) {
    if (this.blockStartLine != null && event.type === "mousedown") return false
    return true
  }

  get estimatedHeight() {
    return this.displayMode ? (this.title ? 64 : 48) : 24
  }
}

/** block replace は StateField のみ可。active 中のブロックは raw 表示 */
export function buildBlockMathDecorations(state, activeStemStartLine = null) {
  const decoRanges = []
  const skipLine = skipLinesForMath(state)
  const stemBlocks = scanStemBlocks(state.doc, skipLine)
  const viewportRange = getViewportLineRange(state)

  for (const block of stemBlocks) {
    if (!block.latex?.trim()) continue
    if (activeStemStartLine != null && block.startLine === activeStemStartLine) continue
    if (
      !blockInViewportRange(block.startLine, block.endLine, viewportRange) &&
      !selectionInLineBlock(state, block.startLine, block.endLine)
    ) {
      continue
    }

    const from = state.doc.line(block.startLine).from
    const to = state.doc.line(block.endLine).to
    if (from >= to) continue

    decoRanges.push(
      Decoration.replace({
        widget: new MathPreviewWidget({
          latex: block.latex,
          displayMode: true,
          blockStartLine: block.startLine,
          editLineNo: stemFirstEditLine(block),
          title: block.title || null
        }),
        block: true,
        inclusive: true
      }).range(from, to)
    )
  }

  return decoRanges.length > 0 ? Decoration.set(decoRanges, true) : Decoration.none
}

function blockMathFieldValue(state, active) {
  return {
    decorations: buildBlockMathDecorations(state, active),
    active
  }
}

function buildInlineMathDecorations(view) {
  const specs = []
  const atomicRanges = []
  const { state } = view
  const editingActive = view.hasFocus
  const viewportRange = getViewportLineRange(state)
  const skipLine = skipLinesForMath(state)
  const stemBlocks = scanStemBlocks(state.doc, skipLine)
  const stemDraftLines = scanStemDraftLineSet(state.doc, skipLine)
  const handledStemLines = new Set()

  for (const block of stemBlocks) {
    for (let n = block.startLine; n <= block.endLine; n++) handledStemLines.add(n)
  }
  for (const n of stemDraftLines) handledStemLines.add(n)

  const activeStem = view.state.field(mathBlockPreviewField, false)?.active
  if (activeStem != null) {
    const activeBlock = stemBlocks.find((b) => b.startLine === activeStem)
    if (activeBlock) {
      for (let n = activeBlock.startLine; n <= activeBlock.endLine; n++) {
        handledStemLines.add(n)
      }
    }
  }

  for (let lineNo = 1; lineNo <= state.doc.lines; lineNo++) {
    if (skipLine(lineNo) || handledStemLines.has(lineNo)) continue
    if (!shouldDecorateEditorLine(view, lineNo, viewportRange)) continue

    const line = state.doc.line(lineNo)
    const text = line.text
    const onLine = editingActive && cursorOnLine(state, line)
    if (onLine) continue

    for (const macro of scanInlineMathMacrosOnLine(text, line.from)) {
      if (editingActive && selectionTouches(state, macro.from, macro.to)) continue

      specs.push({
        from: macro.from,
        to: macro.to,
        deco: Decoration.replace({
          widget: new MathPreviewWidget({
            latex: macro.latex,
            displayMode: macro.display
          })
        })
      })
      atomicRanges.push({ from: macro.from, to: macro.to })
    }
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

const mathBlockPreviewField = StateField.define({
  create(state) {
    return blockMathFieldValue(state, null)
  },
  update(value, tr) {
    let active = value.active
    const explicit = tr.effects.find((e) => e.is(setStemActiveBlock))

    if (explicit !== undefined) {
      active = explicit.value
    } else if (tr.selectionSet && active != null) {
      const skipLine = skipLinesForMath(tr.state)
      const block = scanStemBlocks(tr.state.doc, skipLine).find((b) => b.startLine === active)
      if (!block || !selectionHeadInStemBlock(tr.state, block)) {
        active = null
      }
    }

    const viewportChanged = tr.effects.some((e) => e.is(setViewportLineRange))
    if (tr.docChanged || tr.selectionSet || active !== value.active || viewportChanged) {
      return blockMathFieldValue(tr.state, active)
    }

    return {
      decorations: value.decorations.map(tr.changes),
      active
    }
  },
  provide: (field) => EditorView.decorations.from(field, (v) => v.decorations)
})

const inlineMathPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) {
      const built = buildInlineMathDecorations(view)
      this.decorations = built.decorations
      this.atomicRanges = built.atomicRanges
    }

    update(update) {
      if (
        update.docChanged ||
        update.selectionSet ||
        update.viewportChanged ||
        update.focusChanged ||
        update.startState.field(mathBlockPreviewField).active !==
          update.state.field(mathBlockPreviewField).active
      ) {
        const built = buildInlineMathDecorations(update.view)
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

function tryActivateStemAtClick(event, view) {
  const skipLine = skipLinesForMath(view.state)
  const block = stemBlockAtCoords(view, event.clientX, event.clientY, skipLine)
  if (!block) return false

  event.preventDefault()
  activateStemBlock(view, block.startLine, stemFirstEditLine(block))
  return true
}

function stemClickToEditHandler() {
  return EditorView.domEventHandlers({
    mousedown(event, view) {
      if (event.button !== 0) return false
      if (event.target?.closest?.(".cm-wysiwyg-math--block")) return false
      return tryActivateStemAtClick(event, view)
    }
  })
}

function stemKeyboardEnterHandler() {
  return EditorView.domEventHandlers({
    keydown(event, view) {
      if (view.state.field(mathBlockPreviewField, false)?.active != null) return false

      const block = stemBlockForArrowKey(view.state, event.key, skipLinesForMath(view.state))
      if (!block) return false

      event.preventDefault()
      activateStemBlock(view, block.startLine, stemFirstEditLine(block))
      return true
    }
  })
}

function stemBlurHandler() {
  return EditorView.domEventHandlers({
    blur(_event, view) {
      if (view.state.field(mathBlockPreviewField, false)?.active == null) return false
      view.dispatch({ effects: setStemActiveBlock.of(null) })
      return false
    }
  })
}

function stemSelectionSyncListener() {
  return EditorView.updateListener.of((update) => {
    if (!update.selectionSet) return

    const active = update.state.field(mathBlockPreviewField, false)?.active
    const skipLine = skipLinesForMath(update.state)

    if (active != null) {
      const block = scanStemBlocks(update.state.doc, skipLine).find((b) => b.startLine === active)
      if (!block || !selectionHeadInStemBlock(update.state, block)) {
        update.view.dispatch({ effects: setStemActiveBlock.of(null) })
      }
      return
    }

    const lineNo = update.state.doc.lineAt(update.state.selection.main.head).number
    const block = stemBlockAtLine(update.state, lineNo, skipLine)
    if (block && isStemPreambleLine(lineNo, block)) {
      update.view.dispatch({ effects: setStemActiveBlock.of(block.startLine) })
    }
  })
}

/**
 * Phase 5g CM: `stem:` / `latexmath:` / `[stem]` ブロックの KaTeX プレビュー。
 */
export function mathWysiwygExtension() {
  return [
    mathBlockPreviewField,
    inlineMathPlugin,
    stemClickToEditHandler(),
    stemKeyboardEnterHandler(),
    stemSelectionSyncListener(),
    stemBlurHandler()
  ]
}
