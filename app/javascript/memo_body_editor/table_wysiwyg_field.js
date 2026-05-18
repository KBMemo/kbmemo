import { StateField } from "@codemirror/state"
import { EditorView } from "@codemirror/view"
import {
  allTableBlocks,
  nearestTableLineInBlock,
  isTablePreambleRawLine,
  selectionHeadInTableBlock,
  tableBlockAtCoords,
  tableBlockAtLine,
  tableBlockForArrowKey,
  tableFirstEditLine,
  tableLineFromViewY
} from "./table_syntax"
import { buildTablePreviewDecorations } from "./table_wysiwyg"
import {
  activateTableBlock,
  setTableActiveBlock
} from "./table_wysiwyg_effects"
import {
  getViewportLineRange,
  setViewportLineRange
} from "./viewport_lazy"

export { setTableActiveBlock } from "./table_wysiwyg_effects"

function tableFieldValue(state, active) {
  return {
    decorations: buildTablePreviewDecorations(
      state,
      active,
      getViewportLineRange(state)
    ).decorations,
    active
  }
}

const tablePreviewField = StateField.define({
  create(state) {
    return tableFieldValue(state, null)
  },
  update(value, tr) {
    let active = value.active
    const explicit = tr.effects.find((e) => e.is(setTableActiveBlock))

    if (explicit !== undefined) {
      active = explicit.value
    } else if (tr.selectionSet && active != null) {
      const activeBlock = allTableBlocks(tr.state).find((b) => b.startLine === active)
      if (!activeBlock || !selectionHeadInTableBlock(tr.state, activeBlock)) {
        active = null
      }
    }

    const viewportChanged = tr.effects.some((e) => e.is(setViewportLineRange))
    if (tr.docChanged || tr.selectionSet || active !== value.active || viewportChanged) {
      return tableFieldValue(tr.state, active)
    }

    return {
      decorations: value.decorations.map(tr.changes),
      active
    }
  },
  provide: (field) => EditorView.decorations.from(field, (v) => v.decorations)
})

function tryActivateTableAtClick(event, view) {
  let lineNo
  try {
    lineNo = tableLineFromViewY(view, event.clientY)
  } catch {
    lineNo = null
  }

  if (lineNo != null) {
    const block = tableBlockAtLine(view.state, lineNo)
    if (block) {
      event.preventDefault()
      activateTableBlock(view, block.startLine, lineNo)
      return true
    }
  }

  const block = tableBlockAtCoords(view, event.clientX, event.clientY)
  if (!block) return false

  const nearest = nearestTableLineInBlock(view, event.clientY, block)
  event.preventDefault()
  activateTableBlock(view, block.startLine, nearest)
  return true
}

function tableClickToEditHandler() {
  return EditorView.domEventHandlers({
    mousedown(event, view) {
      if (event.button !== 0) return false
      return tryActivateTableAtClick(event, view)
    }
  })
}

function tableKeyboardEnterHandler() {
  return EditorView.domEventHandlers({
    keydown(event, view) {
      if (view.state.field(tablePreviewField, false)?.active != null) return false

      const block = tableBlockForArrowKey(view.state, event.key)
      if (!block) return false

      event.preventDefault()
      activateTableBlock(
        view,
        block.startLine,
        tableFirstEditLine(view.state.doc, block)
      )
      return true
    }
  })
}

function tableBlurHandler() {
  return EditorView.domEventHandlers({
    blur(_event, view) {
      if (view.state.field(tablePreviewField, false)?.active == null) return false
      view.dispatch({ effects: setTableActiveBlock.of(null) })
      return false
    }
  })
}

/** 選択変更: 表外なら raw 解除 / タイトル・Table 行なら raw へ */
function tableSelectionSyncListener() {
  return EditorView.updateListener.of((update) => {
    if (!update.selectionSet) return

    const active = update.state.field(tablePreviewField, false)?.active

    if (active != null) {
      const block = allTableBlocks(update.state).find((b) => b.startLine === active)
      if (!block || !selectionHeadInTableBlock(update.state, block)) {
        update.view.dispatch({ effects: setTableActiveBlock.of(null) })
      }
      return
    }

    const lineNo = update.state.doc.lineAt(update.state.selection.main.head).number
    const block = tableBlockAtLine(update.state, lineNo)
    if (block && isTablePreambleRawLine(lineNo, block)) {
      update.view.dispatch({ effects: setTableActiveBlock.of(block.startLine) })
    }
  })
}

/**
 * Phase 5d: 表 WYSIWYG（StateField + block replace）。
 */
export function tableWysiwygFieldExtension() {
  return [
    tablePreviewField,
    tableClickToEditHandler(),
    tableKeyboardEnterHandler(),
    tableSelectionSyncListener(),
    tableBlurHandler()
  ]
}
