/** @typedef {'live' | 'wysiwyg' | 'system'} SourceOrigin */

/** @type {string} */
let source = ''

/** @type {Set<(source: string, origin: SourceOrigin) => void>} */
const listeners = new Set()

/**
 * @param {string} next
 */
export function getSource() {
  return source
}

/**
 * @param {string} next
 * @param {SourceOrigin} [origin]
 */
export function setSource(next, origin = 'system') {
  if (source === next) return
  source = next
  for (const listener of listeners) {
    listener(source, origin)
  }
}

/**
 * @param {(source: string, origin: SourceOrigin) => void} listener
 */
export function subscribe(listener) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

/**
 * @param {string} initial
 */
export function initDocument(initial) {
  source = initial
}
