import { loadDocument } from './instance.js'
import { BLOCK_TITLE_LINE } from '../../memo_body_editor/code_block_syntax.js'
import { isTableAttrLine, isTableDelimiterLine } from '../../memo_body_editor/table_syntax.js'

/** @typedef {{ adoc: string, startLine: number, endLine: number }} ParsedEditUnit */

const PAIRED_BLOCK_DELIMITERS = ['----', '....', '====', '____', '****', '--', '+++']

/**
 * Line ranges inside delimited AsciiDoc blocks (listing, literal, quote, …).
 *
 * @param {string[]} lines
 * @returns {[number, number][]}
 */
function getDelimitedLineRanges(lines) {
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
 * @param {string[]} lines
 * @param {number} delimLineIndex 0-based
 */
function parseTablePreambleStartLine(lines, delimLineIndex) {
  /** @type {number[]} */
  const preambleLines = []
  let lineIndex = delimLineIndex - 1

  while (lineIndex >= 0) {
    const trimmed = lines[lineIndex].trim()
    if (!trimmed) break

    if (isTableAttrLine(trimmed)) {
      preambleLines.push(lineIndex)
      lineIndex--
      continue
    }

    if (BLOCK_TITLE_LINE.test(trimmed)) {
      preambleLines.push(lineIndex)
      lineIndex--
      continue
    }

    break
  }

  return preambleLines.length > 0 ? Math.min(...preambleLines) : delimLineIndex
}

/**
 * |=== テーブル全体（タイトル・属性行を含む）の行範囲。
 *
 * @param {string[]} lines
 * @returns {[number, number][]}
 */
function getTableLineRanges(lines) {
  /** @type {[number, number][]} */
  const ranges = []
  let index = 0

  while (index < lines.length) {
    if (!isTableDelimiterLine(lines[index])) {
      index++
      continue
    }

    const startLine = parseTablePreambleStartLine(lines, index)
    let endLine = index
    index++

    while (index < lines.length) {
      if (isTableDelimiterLine(lines[index])) {
        endLine = index
        index++
        break
      }
      endLine = index
      index++
    }

    ranges.push([startLine, endLine])
  }

  return ranges
}

/**
 * @param {string[]} lines
 * @returns {[number, number][]}
 */
function getProtectedLineRanges(lines) {
  return [...getDelimitedLineRanges(lines), ...getTableLineRanges(lines)]
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
  const delimitedRanges = getDelimitedLineRanges(lines)

  return delimitedRanges.map(([start, end]) => ({
    adoc: lines.slice(start, end + 1).join('\n'),
    startLine: start,
    endLine: end,
  }))
}

/**
 * @param {string[]} lines
 * @returns {ParsedEditUnit[]}
 */
function extractTableBlockUnits(lines) {
  return getTableLineRanges(lines).map(([start, end]) => ({
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
  const units = [
    ...extractDelimitedBlockUnits(lines),
    ...extractTableBlockUnits(lines),
  ]

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
  const deduped = dedupeContainedUnits(units)
  units.length = 0
  units.push(...deduped)
  appendTrailingUnits(lines, units, protectedRanges)

  return units
}

/**
 * 内包される編集ユニットを除去（テーブル保護後も visitBlocks が部分一致する場合がある）
 *
 * @param {ParsedEditUnit[]} units
 * @returns {ParsedEditUnit[]}
 */
function dedupeContainedUnits(units) {
  const sorted = [...units].sort((a, b) => a.startLine - b.startLine || a.endLine - b.endLine)
  /** @type {ParsedEditUnit[]} */
  const kept = []

  for (const unit of sorted) {
    const contained = kept.some(
      (existing) =>
        unit.startLine >= existing.startLine && unit.endLine <= existing.endLine
    )
    if (!contained) kept.push(unit)
  }

  return kept
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
 * @param {number} cursorLine 0-based
 * @returns {{ tableAdoc: string, paragraphAdoc: string, tableEndLine: number } | null}
 */
export function getTableParagraphSplit(source, cursorLine) {
  const lines = source.split('\n')
  const tableRanges = getTableLineRanges(lines)
  if (tableRanges.length === 0) return null

  const [tableStart, tableEnd] = tableRanges[tableRanges.length - 1]
  if (!isTableDelimiterLine(lines[tableEnd] ?? '')) return null
  if (cursorLine <= tableEnd) return null
  if (tableEnd + 1 >= lines.length) return null

  const tableAdoc = lines.slice(tableStart, tableEnd + 1).join('\n')
  const paragraphAdoc = lines.slice(tableEnd + 1).join('\n').replace(/^\n+/, '')

  return { tableAdoc, paragraphAdoc, tableEndLine: tableEnd }
}

/**
 * @param {string} source
 * @param {number} separatorStartLine 0-based first line after preceding block
 * @param {number} selectionStart
 */
export function getCaretInFollowingBlock(source, separatorStartLine, selectionStart) {
  const rawAfter = source.split('\n').slice(separatorStartLine).join('\n')
  const blockAdoc = rawAfter.replace(/^\n+/, '')
  const leadingRemoved = rawAfter.length - blockAdoc.length
  const regionStart = getSourceOffsetForLine(source, separatorStartLine)
  return Math.max(0, Math.min(selectionStart - regionStart - leadingRemoved, blockAdoc.length))
}

/**
 * @param {string} source
 * @param {number} [cursorLine] 0-based; when set, enables table→paragraph split detection
 */
export function shouldSplitEditUnits(source, cursorLine) {
  if (cursorLine != null && getTableParagraphSplit(source, cursorLine)) {
    return true
  }

  if (!hasBlankLineSeparator(source)) return false

  const units = parseEditUnitsFromSource(source).filter((unit) => unit.adoc.trim())
  return units.length > 1
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
