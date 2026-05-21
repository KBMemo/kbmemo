import { redo, redoDepth, undo, undoDepth } from '@codemirror/commands'

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export function canUndoInView(view) {
  return undoDepth(view.state) > 0
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export function canRedoInView(view) {
  return redoDepth(view.state) > 0
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export function undoInView(view) {
  if (!undo(view)) return
  view.focus()
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export function redoInView(view) {
  if (!redo(view)) return
  view.focus()
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export async function copyFromView(view) {
  const { from, to } = view.state.selection.main
  if (from === to) return

  const text = view.state.sliceDoc(from, to)
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    copyWithExecCommand(text)
  }
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export async function cutFromView(view) {
  const { from, to } = view.state.selection.main
  if (from === to) return

  const text = view.state.sliceDoc(from, to)
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    copyWithExecCommand(text)
  }

  view.dispatch({
    changes: { from, to, insert: '' },
    selection: { anchor: from },
  })
  view.focus()
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export async function pasteToView(view) {
  let text = ''
  try {
    text = await navigator.clipboard.readText()
  } catch {
    view.focus()
    return
  }

  if (!text) return

  const { from, to } = view.state.selection.main
  view.dispatch({
    changes: { from, to, insert: text },
    selection: { anchor: from + text.length },
  })
  view.focus()
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export function selectAllInView(view) {
  view.dispatch({
    selection: { anchor: 0, head: view.state.doc.length },
  })
  view.focus()
}

/**
 * @param {string} text
 */
function copyWithExecCommand(text) {
  const textarea = document.createElement('textarea')
  textarea.value = text
  textarea.setAttribute('readonly', '')
  textarea.style.position = 'fixed'
  textarea.style.left = '-9999px'
  document.body.append(textarea)
  textarea.select()
  document.execCommand('copy')
  textarea.remove()
}

/**
 * @param {string} [text]
 */
export async function copyPlainText(text) {
  const value = text ?? window.getSelection()?.toString() ?? ''
  if (!value) return
  try {
    await navigator.clipboard.writeText(value)
  } catch {
    copyWithExecCommand(value)
  }
}
