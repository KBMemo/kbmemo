/**
 * @param {string} line
 */
export function isBlankLine(line) {
  return line.trim() === ''
}

/**
 * Leading whitespace to continue an indent literal line (minimum one space).
 *
 * @param {string} line
 */
export function literalContinuationIndent(line) {
  const match = line.match(/^(\s+)/)
  if (match) return match[1]
  return ' '
}

/**
 * @param {string[]} lines
 * @param {number} lineIndex
 */
export function indentForLiteralContinuation(lines, lineIndex) {
  for (let index = lineIndex; index >= 0; index--) {
    const line = lines[index] ?? ''
    if (!isBlankLine(line)) {
      return literalContinuationIndent(line)
    }
    const spacesOnly = line.match(/^(\s+)$/)
    if (spacesOnly) return spacesOnly[1]
  }
  return ' '
}

/**
 * @param {string} source
 * @param {number} blankLineIndex 0-based index of the blank line
 * @param {{ preserveIndent?: boolean }} [options]
 */
function splitBlockAtBlankLine(source, blankLineIndex, { preserveIndent = false } = {}) {
  const lines = source.split('\n')
  const beforeLines = lines.slice(0, blankLineIndex)
  while (beforeLines.length > 0 && isBlankLine(beforeLines[beforeLines.length - 1])) {
    beforeLines.pop()
  }
  const beforeAdoc = preserveIndent
    ? beforeLines.join('\n').trimEnd()
    : beforeLines.join('\n').trim()

  const afterLines = lines.slice(blankLineIndex + 1)
  while (afterLines.length > 0 && isBlankLine(afterLines[0])) {
    afterLines.shift()
  }

  return {
    beforeAdoc,
    afterAdoc: afterLines.join('\n'),
  }
}

/**
 * Split indent-literal source at a blank line into content before and after.
 *
 * @param {string} source
 * @param {number} blankLineIndex 0-based index of the blank line
 */
export function splitIndentLiteralAtBlankLine(source, blankLineIndex) {
  const { beforeAdoc, afterAdoc } = splitBlockAtBlankLine(source, blankLineIndex, {
    preserveIndent: true,
  })
  return { literalAdoc: beforeAdoc, afterAdoc }
}

/**
 * Split a normal paragraph block at a blank line.
 *
 * @param {string} source
 * @param {number} blankLineIndex 0-based index of the blank line
 */
export function splitParagraphAtBlankLine(source, blankLineIndex) {
  return splitBlockAtBlankLine(source, blankLineIndex, { preserveIndent: false })
}

/**
 * @param {string} adoc
 */
export function isIndentLiteralBlock(adoc) {
  const firstLine = adoc.split('\n')[0] ?? ''
  return firstLine.startsWith(' ')
}

/**
 * @param {string} text Plain literal text (no leading indent).
 */
export function indentLiteralFromPlainText(text) {
  return text
    .split('\n')
    .map((line) => ` ${line}`)
    .join('\n')
    .trimEnd()
}

/**
 * Normalize a block segment for document assembly without losing indent literals.
 *
 * @param {string} text
 */
export function normalizeBlockSegmentText(text) {
  if (isIndentLiteralBlock(text)) {
    return text.trimEnd()
  }
  return text.trim()
}

/**
 * @param {string} adoc
 */
export function adocForBlockConversion(adoc) {
  if (!adoc.trim()) return adoc
  return isIndentLiteralBlock(adoc) ? adoc.trimEnd() : adoc.trim()
}

/** @type {string} */
export const INDENT_LITERAL_DATA_ATTR = 'kbmemoIndentLiteral'
