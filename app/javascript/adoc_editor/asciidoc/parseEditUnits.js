import { loadDocument } from './instance.js'

/** @typedef {{ adoc: string, startLine: number, endLine: number }} ParsedEditUnit */

const PAIRED_BLOCK_DELIMITERS = ['----', '....', '====', '____', '****', '--', '+++']

/**
 * Line ranges inside delimited AsciiDoc blocks (listing, literal, quote, …).
 *
 * @param {string[]} lines
 * @returns {[number, number][]}
 */
function getProtectedLineRanges(lines) {
  /** @type {[number, number][]} */
  const ranges = []
  let index = 0

  while (index < lines.length) {
    let start = index
    const trimmed = lines[index].trim()

    if (/^\[[^\]]+\]$/.test(trimmed) && index + 1 < lines.length) {
      const nextTrimmed = lines[index + 1].trim()
      if (PAIRED_BLOCK_DELIMITERS.includes(nextTrimmed)) {
        start = index
        index++
      }
    }

    const delimiter = lines[index]?.trim()
    if (delimiter && PAIRED_BLOCK_DELIMITERS.includes(delimiter)) {
      const openLine = index
      let closeLine = openLine
      let scan = openLine + 1

      while (scan < lines.length) {
        if (lines[scan].trim() === delimiter) {
          closeLine = scan
          break
        }
        scan++
      }

      if (closeLine === openLine) {
        closeLine = lines.length - 1
      }

      ranges.push([start, closeLine])
      index = closeLine + 1
      continue
    }

    index++
  }

  return ranges
}

/**
 * @param {number} lineIndex
 * @param {[number, number][]} ranges
 */
function isLineProtected(lineIndex, ranges) {
  return ranges.some(([start, end]) => lineIndex >= start && lineIndex <= end)
}

/**
 * @param {string} source
 */
export function hasBlankLineSeparator(source) {
  const lines = source.split('\n')
  const protectedRanges = getProtectedLineRanges(lines)

  for (let index = 0; index < lines.length; index++) {
    if (lines[index].trim() !== '') continue
    if (isLineProtected(index, protectedRanges)) continue
    if (index === lines.length - 1) continue
    return true
  }

  return false
}

/**
 * @param {number} startLine
 * @param {number} endLine
 * @param {[number, number][]} ranges
 */
function isRangeInsideProtected(startLine, endLine, ranges) {
  return ranges.some(([start, end]) => startLine >= start && endLine <= end)
}

/**
 * @param {string[]} lines
 * @returns {ParsedEditUnit[]}
 */
function extractDelimitedBlockUnits(lines) {
  const protectedRanges = getProtectedLineRanges(lines)

  return protectedRanges.map(([start, end]) => ({
    adoc: lines.slice(start, end + 1).join('\n'),
    startLine: start,
    endLine: end,
  }))
}

/**
 * Parse AsciiDoc source into edit units with 0-based line ranges.
 *
 * @param {string} source
 * @returns {ParsedEditUnit[]}
 */
export function parseEditUnitsFromSource(source) {
  const lines = source.split('\n')

  if (!source.trim()) {
    return [{ adoc: '', startLine: 0, endLine: Math.max(0, lines.length - 1) }]
  }

  const protectedRanges = getProtectedLineRanges(lines)
  /** @type {ParsedEditUnit[]} */
  const units = extractDelimitedBlockUnits(lines)

  const doc = loadDocument(source)

  const firstLine = lines[0] ?? ''
  if (/^=\s+\S/.test(firstLine) && !/^==/.test(firstLine)) {
    if (!isRangeInsideProtected(0, 0, protectedRanges)) {
      units.push({ adoc: firstLine.trim(), startLine: 0, endLine: 0 })
    }
  }

  visitBlocks(doc, units, protectedRanges)

  if (units.length === 0) {
    return [{ adoc: source, startLine: 0, endLine: lines.length - 1 }]
  }

  units.sort((a, b) => a.startLine - b.startLine)
  appendTrailingUnits(lines, units, protectedRanges)

  return units
}

/**
 * @param {import('@asciidoctor/core').Document | import('@asciidoctor/core').Section | import('@asciidoctor/core').Block} node
 * @param {ParsedEditUnit[]} units
 * @param {[number, number][]} protectedRanges
 */
function visitBlocks(node, units, protectedRanges) {
  const ctx = node.getContext?.()
  if (ctx === 'document' || ctx === 'section') {
    if (ctx === 'section') {
      const level = node.getLevel()
      const marker = '='.repeat(level + 1)
      const title = node.getTitle()
      const line = (node.getLineNumber() ?? 1) - 1
      if (!isRangeInsideProtected(line, line, protectedRanges)) {
        units.push({ adoc: `${marker} ${title}`, startLine: line, endLine: line })
      }
    }

    for (const block of node.getBlocks()) {
      visitBlocks(block, units, protectedRanges)
    }
    return
  }

  const blockSource = node.getSource?.()
  if (!blockSource) return

  const startLine = (node.getLineNumber() ?? 1) - 1
  const endLine = startLine + blockSource.split('\n').length - 1
  if (isRangeInsideProtected(startLine, endLine, protectedRanges)) {
    return
  }

  units.push({ adoc: blockSource, startLine, endLine })
}

/**
 * @param {string} source
 */
export function shouldSplitEditUnits(source) {
  if (!hasBlankLineSeparator(source)) return false
  return parseEditUnitsFromSource(source).length > 1
}

/**
 * @param {string[]} lines
 * @param {ParsedEditUnit[]} units
 * @param {[number, number][]} protectedRanges
 */
function appendTrailingUnits(lines, units, protectedRanges) {
  const lastUnit = units[units.length - 1]
  let index = lastUnit.endLine + 1

  while (index < lines.length) {
    if (isLineProtected(index, protectedRanges)) {
      index++
      continue
    }

    if (lines[index].trim() === '') {
      // Enter 1 回分の末尾改行は空行区切りとみなさない
      if (index === lines.length - 1) {
        return
      }

      const start = index
      index++
      while (index < lines.length && lines[index].trim() === '') {
        index++
      }

      let endLine = index - 1
      if (endLine > start && endLine === lines.length - 1 && lines[endLine] === '') {
        endLine--
      }

      units.push({ adoc: '', startLine: start, endLine })
      continue
    }

    units.push({ adoc: lines[index], startLine: index, endLine: index })
    index++
  }
}

/**
 * @param {ParsedEditUnit[]} units
 * @param {number} cursorLine 0-based
 */
export function getActiveUnitIndex(units, cursorLine) {
  for (let i = 0; i < units.length; i++) {
    const unit = units[i]
    if (cursorLine >= unit.startLine && cursorLine <= unit.endLine) {
      return i
    }
  }

  for (let i = 0; i < units.length; i++) {
    if (units[i].startLine > cursorLine) {
      return i
    }
  }

  return units.length - 1
}

/**
 * @param {string} source
 * @param {number} line 0-based
 */
export function getSourceOffsetForLine(source, line) {
  if (line <= 0) return 0

  let offset = 0
  const lines = source.split('\n')
  for (let i = 0; i < line && i < lines.length; i++) {
    offset += lines[i].length + 1
  }
  return offset
}

/**
 * @param {string} source
 * @param {ParsedEditUnit} unit
 * @param {number} selectionStart
 */
export function getCaretOffsetInUnit(source, unit, selectionStart) {
  const unitStart = getSourceOffsetForLine(source, unit.startLine)
  const caret = selectionStart - unitStart
  return Math.max(0, Math.min(caret, unit.adoc.length))
}
