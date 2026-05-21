import { normalizeDocumentSource } from './wysiwygDocumentSearch.js'

/** @typedef {{ source: string, cursor: number }} WysiwygHistoryEntry */

/** @typedef {{
 *   canUndo: () => boolean
 *   canRedo: () => boolean
 *   undo: () => boolean
 *   redo: () => boolean
 * }} DocumentHistoryController */

/**
 * @param {string} [initialSource]
 */
export function createWysiwygHistory(initialSource = '', initialCursor = 0) {
  /** @type {WysiwygHistoryEntry[]} */
  let undoStack = []
  /** @type {WysiwygHistoryEntry[]} */
  let redoStack = []
  /** @type {WysiwygHistoryEntry} */
  let current = { source: initialSource, cursor: initialCursor }

  return {
    reset(source, cursor = 0) {
      current = { source: normalizeDocumentSource(source), cursor }
      undoStack = []
      redoStack = []
    },
    getCurrent() {
      return current.source
    },
    getCurrentEntry() {
      return current
    },
    canUndo() {
      return undoStack.length > 0
    },
    canRedo() {
      return redoStack.length > 0
    },
    /**
     * @param {string} next
     * @param {number} cursor
     * @param {number} undoCursor
     */
    commit(next, cursor, undoCursor) {
      const normalizedNext = normalizeDocumentSource(next)
      const normalizedCurrent = normalizeDocumentSource(current.source)
      if (normalizedNext === normalizedCurrent) return false
      undoStack.push({ source: normalizedCurrent, cursor: undoCursor })
      current = { source: normalizedNext, cursor }
      redoStack = []
      return true
    },
    /**
     * @param {string} source
     * @param {number} [cursor]
     */
    setCurrent(source, cursor = 0) {
      current = { source: normalizeDocumentSource(source), cursor }
    },
    /**
     * @param {number} cursor
     * @returns {WysiwygHistoryEntry | null}
     */
    undo(cursor) {
      if (undoStack.length === 0) return null
      redoStack.push({ source: current.source, cursor })
      current = undoStack.pop()
      return current
    },
    /**
     * @param {number} cursor
     * @returns {WysiwygHistoryEntry | null}
     */
    redo(cursor) {
      if (redoStack.length === 0) return null
      undoStack.push({ source: current.source, cursor })
      current = redoStack.pop()
      return current
    },
  }
}

/**
 * @param {KeyboardEvent} event
 */
export function isModZ(event) {
  return (
    (event.ctrlKey || event.metaKey) &&
    !event.shiftKey &&
    !event.altKey &&
    event.key.toLowerCase() === 'z'
  )
}

/**
 * @param {KeyboardEvent} event
 */
export function isModRedo(event) {
  const key = event.key.toLowerCase()
  if (!(event.ctrlKey || event.metaKey) || event.altKey) return false
  if (key === 'y' && !event.shiftKey) return true
  if (key === 'z' && event.shiftKey) return true
  return false
}
