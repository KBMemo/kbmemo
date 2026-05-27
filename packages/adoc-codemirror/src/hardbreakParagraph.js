/** AsciiDoc explicit line break: trailing space + plus at end of line. */
export const HARD_BREAK_LINE_PATTERN = /\s\+$/

/**
 * @param {string} lineText
 */
export function lineHasHardBreakContinuation(lineText) {
  return HARD_BREAK_LINE_PATTERN.test(lineText)
}

/**
 * @param {string} lineText Content before the hard break (no trailing newline).
 */
export function formatHardBreakLine(lineText) {
  const trimmed = lineText.replace(/\s+$/, '')
  if (!trimmed) return null
  if (lineHasHardBreakContinuation(trimmed)) return trimmed
  return `${trimmed} +`
}

/**
 * @param {HTMLElement} el
 */
export function isEmptyParagraphMarkerBr(el) {
  return el.tagName.toLowerCase() === 'br' && el.classList.contains('wysiwyg-empty-paragraph-marker')
}
