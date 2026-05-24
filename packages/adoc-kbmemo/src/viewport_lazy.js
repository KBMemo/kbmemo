import { StateEffect, StateField } from "@codemirror/state"
import { EditorView, ViewPlugin } from "@codemirror/view"

/** ビューポート上下に装飾を先行生成する行数 */
export const WYSIWYG_VIEWPORT_BUFFER_LINES = 48

export const setViewportLineRange = StateEffect.define()

export const viewportLineRangeField = StateField.define({
  create(state) {
    const lines = Math.max(1, state.doc.lines)
    return { minLine: 1, maxLine: Math.min(lines, 120) }
  },
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setViewportLineRange)) return effect.value
    }
    return value
  }
})

function lineRangeKey(range) {
  return `${range.minLine}:${range.maxLine}`
}

function publishViewportRange(view) {
  if (!view.dom?.isConnected) return
  const range = computeViewportLineRange(view)
  const current = view.state.field(viewportLineRangeField, false)
  if (!current || lineRangeKey(current) === lineRangeKey(range)) return
  view.dispatch({ effects: setViewportLineRange.of(range) })
}

function schedulePublishViewportRange(view) {
  queueMicrotask(() => publishViewportRange(view))
}

/**
 * ビューポート変更時に可視行範囲を StateField へ反映（表 StateField 等が参照）。
 */
export function viewportLineRangeSyncExtension() {
  return [
    viewportLineRangeField,
    EditorView.updateListener.of((update) => {
      if (update.viewportChanged || update.docChanged) {
        schedulePublishViewportRange(update.view)
      }
    }),
    ViewPlugin.fromClass(
      class {
        constructor(view) {
          schedulePublishViewportRange(view)
        }
      }
    )
  ]
}

export function getViewportLineRange(state) {
  return state.field(viewportLineRangeField)
}

export function computeViewportLineRange(view, bufferLines = WYSIWYG_VIEWPORT_BUFFER_LINES) {
  const { state } = view
  if (state.doc.lines === 0) return { minLine: 1, maxLine: 1 }

  const { from, to } = view.viewport
  const endPos = state.doc.length === 0 ? 0 : Math.max(0, Math.min(to, state.doc.length - 1))
  const first = state.doc.lineAt(from).number
  const last = state.doc.lineAt(endPos).number

  return {
    minLine: Math.max(1, first - bufferLines),
    maxLine: Math.min(state.doc.lines, last + bufferLines)
  }
}

export function lineInViewportRange(lineNo, range) {
  return lineNo >= range.minLine && lineNo <= range.maxLine
}

export function blockInViewportRange(startLine, endLine, range) {
  return endLine >= range.minLine && startLine <= range.maxLine
}

export function cursorOnLine(state, lineNo) {
  return state.selection.ranges.some((range) => state.doc.lineAt(range.head).number === lineNo)
}

export function selectionInLineBlock(state, startLine, endLine) {
  return state.selection.ranges.some((range) => {
    const anchorLine = state.doc.lineAt(range.anchor).number
    const headLine = state.doc.lineAt(range.head).number
    const minLine = Math.min(anchorLine, headLine)
    const maxLine = Math.max(anchorLine, headLine)
    return maxLine >= startLine && minLine <= endLine
  })
}

/** 行単位装飾: ビューポート内、またはフォーカス中のカーソル行 */
export function shouldDecorateEditorLine(view, lineNo, range) {
  if (lineInViewportRange(lineNo, range)) return true
  if (view.hasFocus && cursorOnLine(view.state, lineNo)) return true
  return false
}

/** ブロック装飾: 表・コードブロック等はブロック全体をまとめて判定 */
export function shouldDecorateEditorBlock(view, startLine, endLine, range) {
  if (blockInViewportRange(startLine, endLine, range)) return true
  if (selectionInLineBlock(view.state, startLine, endLine)) return true
  return false
}
