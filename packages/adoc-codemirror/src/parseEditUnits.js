import { loadDocument } from './instance.js'
import { BLOCK_TITLE_LINE } from '@kbmemo/adoc-kbmemo'
import { extractStemBlockUnitsFromLines } from '@kbmemo/adoc-kbmemo'
import { isTableAttrLine, isTableDelimiterLine } from '@kbmemo/adoc-kbmemo'

/** @typedef {{ adoc: string, startLine: number, endLine: number }} ParsedEditUnit */

const PAIRED_BLOCK_DELIMITERS = ['++++', '////', '----', '....', '====', '____', '****', '--', '+++']
const BLOCK_ATTR_LINE = /^\[[^\]]+\]$/
const ADMONITION_LABEL_LINE = /^(NOTE|TIP|IMPORTANT|WARNING|CAUTION):/

/**
 * @param {string[]} lines
 * @param {number} delimLineIndex 0-based
 */
function parseDelimitedPreambleStartLine(lines, delimLineIndex) {
  let lineIndex = delimLineIndex - 1
  /** @type {number[]} */
  const preambleLines = []

  while (lineIndex >= 0) {
    const trimmed = lines[lineIndex].trim()
    if (!trimmed) break

    if (BLOCK_ATTR_LINE.test(trimmed) || BLOCK_TITLE_LINE.test(trimmed)) {
      preambleLines.push(lineIndex)
      lineIndex--
      continue
    }

    break
  }

  return preambleLines.length > 0 ? Math.min(...preambleLines) : delimLineIndex
}

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
    const delimiter = lines[index]?.trim()
    if (delimiter && PAIRED_BLOCK_DELIMITERS.includes(delimiter)) {
      const openLine = index
      const startLine = parseDelimitedPreambleStartLine(lines, openLine)
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

      ranges.push([startLine, closeLine])
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
  return [
    ...getDelimitedLineRanges(lines),
    ...getTableLineRanges(lines),
    ...getStemLineRanges(lines),
  ]
}

/**
 * @param {string[]} lines
 * @returns {[number, number][]}
 */
function getStemLineRanges(lines) {
  return extractStemBlockUnitsFromLines(lines).map((unit) => [unit.startLine, unit.endLine])
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
 * @param {string[]} lines
 * @returns {ParsedEditUnit[]}
 */
function extractStemBlockUnits(lines) {
  return extractStemBlockUnitsFromLines(lines)
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
    ...extractStemBlockUnits(lines),
  ]

  const doc = loadDocument(source)

  const firstLine = lines[0] ?? ''
  if (/^=\s+\S/.test(firstLine) && !/^==/.test(firstLine)) {
    if (!isRangeInsideProtected(0, 0, protectedRanges)) {
      units.push({ adoc: firstLine.trim(), startLine: 0, endLine: 0 })
    }
  }

  visitBlocks(doc, units, protectedRanges, lines)

  if (units.length === 0) {
    return [{ adoc: source, startLine: 0, endLine: lines.length - 1 }]
  }

  units.sort((a, b) => a.startLine - b.startLine)
  let deduped = dedupeContainedUnits(units)
  deduped = fillGapUnits(lines, deduped, protectedRanges)
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
 * @param {import('@asciidoctor/core').Block} node
 * @param {string[]} lines
 */
function blockUnitSource(node, lines) {
  const startLine = (node.getLineNumber() ?? 1) - 1
  const blockSource = node.getSource?.() ?? ''
  const endLine = startLine + Math.max(0, blockSource.split('\n').length - 1)
  const raw = lines.slice(startLine, endLine + 1).join('\n')
  const firstLine = lines[startLine] ?? ''
  const firstTrimmed = firstLine.trim()

  if (/^include::/.test(firstTrimmed)) {
    return raw
  }

  if (node.getContext?.() === 'literal' && firstLine.startsWith(' ')) {
    return raw
  }

  return blockSource
}

/**
 * @param {import('@asciidoctor/core').Document | import('@asciidoctor/core').Section | import('@asciidoctor/core').Block | import('@asciidoctor/core').List} node
 * @param {ParsedEditUnit[]} units
 * @param {[number, number][]} protectedRanges
 * @param {string[]} lines
 */
function visitBlocks(node, units, protectedRanges, lines) {
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
      visitBlocks(block, units, protectedRanges, lines)
    }
    return
  }

  if (ctx === 'ulist' || ctx === 'olist') {
    pushListUnit(node, units, protectedRanges, lines)
    return
  }

  if (ctx === 'dlist') {
    pushDlistUnit(node, units, protectedRanges, lines)
    return
  }

  if (ctx === 'quote') {
    pushQuoteUnit(node, units, protectedRanges, lines)
    return
  }

  if (ctx === 'admonition') {
    pushAdmonitionUnit(node, units, protectedRanges, lines)
    return
  }

  const blockSource = node.getSource?.()
  if (!blockSource) return

  const startLine = (node.getLineNumber() ?? 1) - 1
  const endLine = startLine + blockSource.split('\n').length - 1
  if (isRangeInsideProtected(startLine, endLine, protectedRanges)) {
    return
  }

  units.push({ adoc: blockUnitSource(node, lines), startLine, endLine })
}

/**
 * リスト直前のブロック属性（[%interactive] 等）とタイトル行をユニットに含める。
 *
 * @param {number} contentStartLine 0-based first list item line
 * @param {string[]} lines
 */
function listUnitStartLine(contentStartLine, lines) {
  let startLine = contentStartLine

  while (startLine > 0) {
    const prevTrimmed = lines[startLine - 1]?.trim() ?? ''
    if (!prevTrimmed) break

    if (BLOCK_ATTR_LINE.test(prevTrimmed) || BLOCK_TITLE_LINE.test(prevTrimmed)) {
      startLine--
      continue
    }

    break
  }

  return startLine
}

/**
 * @param {import('@asciidoctor/core').List} node
 * @param {ParsedEditUnit[]} units
 * @param {[number, number][]} protectedRanges
 * @param {string[]} lines
 */
function pushListUnit(node, units, protectedRanges, lines) {
  const contentStartLine = (node.getLineNumber() ?? 1) - 1
  const startLine = listUnitStartLine(contentStartLine, lines)
  const endLine = listBlockEndLine(node)
  if (isRangeInsideProtected(startLine, endLine, protectedRanges)) return

  units.push({
    adoc: lines.slice(startLine, endLine + 1).join('\n'),
    startLine,
    endLine,
  })
}

/**
 * @param {import('@asciidoctor/core').List | import('@asciidoctor/core').ListItem} node
 */
function listBlockEndLine(node) {
  let endLine = (node.getLineNumber() ?? 1) - 1
  for (const item of node.getBlocks?.() ?? []) {
    endLine = Math.max(endLine, listItemEndLine(item))
  }
  return endLine
}

/**
 * @param {import('@asciidoctor/core').ListItem} item
 */
function listItemEndLine(item) {
  let endLine = (item.getLineNumber() ?? 1) - 1

  for (const block of item.getBlocks?.() ?? []) {
    const ctx = block.getContext?.()
    if (ctx === 'ulist' || ctx === 'olist') {
      endLine = Math.max(endLine, listBlockEndLine(block))
      continue
    }

    const src = block.getSource?.()
    if (!src) continue

    const line = (block.getLineNumber() ?? 1) - 1
    endLine = Math.max(endLine, line + src.split('\n').length - 1)
  }

  return endLine
}

/**
 * @param {string} trimmed
 */
function isEditUnitHardStop(trimmed) {
  if (!trimmed) return false
  if (trimmed === '[qanda]') return false
  if (/^=+\s/.test(trimmed)) return true
  if (PAIRED_BLOCK_DELIMITERS.includes(trimmed)) return true
  if (isTableDelimiterLine(trimmed)) return true
  if (ADMONITION_LABEL_LINE.test(trimmed)) return true
  if (/^image::/.test(trimmed)) return true
  if (/^audio::/.test(trimmed)) return true
  if (/^video::/.test(trimmed)) return true
  if (/^include::/.test(trimmed)) return true
  if (BLOCK_ATTR_LINE.test(trimmed)) return true
  if (BLOCK_TITLE_LINE.test(trimmed)) return true
  if (/^\/\//.test(trimmed)) return true
  return false
}

/**
 * @param {string} text
 */
function isDlistContentLine(text) {
  const trimmed = text.trim()
  if (!trimmed) return false
  if (trimmed === '[qanda]') return true
  if (/::/.test(trimmed)) return true
  if (trimmed === '+') return true
  if (/^[*.\[]/.test(trimmed)) return true
  return false
}

/**
 * @param {string} text
 */
function isDlistContinuationLine(text) {
  return /^\s+\S/.test(text)
}

/**
 * @param {string[]} lines
 * @param {number} startLine 0-based
 */
function dlistEndLine(lines, startLine) {
  let endLine = startLine
  let inDlist = false

  for (let index = startLine; index < lines.length; index++) {
    const text = lines[index]
    const trimmed = text.trim()

    if (trimmed === '') {
      endLine = index
      continue
    }

    if (trimmed === '[qanda]') {
      endLine = index
      continue
    }

    if (isDlistContentLine(text) || isDlistContinuationLine(text)) {
      inDlist = true
      endLine = index
      continue
    }

    if (inDlist && !isEditUnitHardStop(trimmed)) {
      endLine = index
      continue
    }

    if (isEditUnitHardStop(trimmed)) break

    break
  }

  return endLine
}

/**
 * @param {number} contentStartLine 0-based first dlist line
 * @param {string[]} lines
 */
function dlistUnitStartLine(contentStartLine, lines) {
  let startLine = contentStartLine

  while (startLine > 0) {
    const prevTrimmed = lines[startLine - 1]?.trim() ?? ''
    if (!prevTrimmed) break

    if (prevTrimmed === '[qanda]' || BLOCK_ATTR_LINE.test(prevTrimmed)) {
      startLine--
      continue
    }

    break
  }

  return startLine
}

/**
 * @param {import('@asciidoctor/core').Block} node
 * @param {ParsedEditUnit[]} units
 * @param {[number, number][]} protectedRanges
 * @param {string[]} lines
 */
function pushDlistUnit(node, units, protectedRanges, lines) {
  const contentStartLine = (node.getLineNumber() ?? 1) - 1
  const startLine = dlistUnitStartLine(contentStartLine, lines)
  const endLine = dlistEndLine(lines, startLine)
  if (isRangeInsideProtected(startLine, endLine, protectedRanges)) return

  units.push({
    adoc: lines.slice(startLine, endLine + 1).join('\n'),
    startLine,
    endLine,
  })
}

/**
 * @param {import('@asciidoctor/core').Block} node
 * @param {ParsedEditUnit[]} units
 * @param {[number, number][]} protectedRanges
 * @param {string[]} lines
 */
function pushQuoteUnit(node, units, protectedRanges, lines) {
  const { adoc, startLine, endLine } = quoteUnitFromNode(node, lines)
  if (!adoc.trim()) return
  if (isRangeInsideProtected(startLine, endLine, protectedRanges)) return

  units.push({ adoc, startLine, endLine })
}

/**
 * @param {import('@asciidoctor/core').Block} node
 * @param {string[]} lines
 */
function quoteUnitFromNode(node, lines) {
  const contentStartLine = (node.getLineNumber() ?? 1) - 1
  const content = node.getSource?.() ?? ''
  const style = node.getStyle?.()

  if (style === 'quote') {
    const prevTrimmed = contentStartLine > 0 ? lines[contentStartLine - 1]?.trim() : ''
    if (prevTrimmed.startsWith('[quote')) {
      const startLine = contentStartLine - 1
      const endLine = contentStartLine + Math.max(0, content.split('\n').length - 1)
      return {
        adoc: lines.slice(startLine, endLine + 1).join('\n'),
        startLine,
        endLine,
      }
    }
  }

  const endLine = contentStartLine + Math.max(0, content.split('\n').length - 1)
  return { adoc: content, startLine: contentStartLine, endLine }
}

/**
 * @param {import('@asciidoctor/core').Block} node
 * @param {ParsedEditUnit[]} units
 * @param {[number, number][]} protectedRanges
 * @param {string[]} lines
 */
function pushAdmonitionUnit(node, units, protectedRanges, lines) {
  const { adoc, startLine, endLine } = admonitionUnitFromNode(node, lines)
  if (!adoc.trim()) return
  if (isRangeInsideProtected(startLine, endLine, protectedRanges)) return

  units.push({ adoc, startLine, endLine })
}

/**
 * Asciidoctor の admonition は getSource() が本文のみのため、NOTE:/[NOTE] 形式を復元する。
 *
 * @param {import('@asciidoctor/core').Block} node
 * @param {string[]} lines
 */
function admonitionUnitFromNode(node, lines) {
  const contentStartLine = (node.getLineNumber() ?? 1) - 1
  const content = node.getSource?.() ?? ''
  const style = node.getStyle?.()

  if (style) {
    const prevLine = contentStartLine > 0 ? lines[contentStartLine - 1]?.trim() : ''
    if (prevLine === `[${style}]`) {
      const startLine = contentStartLine - 1
      const endLine = contentStartLine + Math.max(0, content.split('\n').length - 1)
      return {
        adoc: lines.slice(startLine, endLine + 1).join('\n'),
        startLine,
        endLine,
      }
    }

    if (content.includes('\n')) {
      return {
        adoc: `[${style}]\n${content}`,
        startLine: contentStartLine,
        endLine: contentStartLine + content.split('\n').length,
      }
    }

    return {
      adoc: `${style}: ${content}`,
      startLine: contentStartLine,
      endLine: contentStartLine,
    }
  }

  const endLine = contentStartLine + Math.max(0, content.split('\n').length - 1)
  return { adoc: content, startLine: contentStartLine, endLine }
}

/**
 * visitBlocks で拾えなかった行範囲をユニット化する（リスト等の取りこぼし防止）。
 *
 * @param {string[]} lines
 * @param {ParsedEditUnit[]} units
 * @param {[number, number][]} protectedRanges
 */
function fillGapUnits(lines, units, protectedRanges) {
  if (units.length === 0) return units

  const sorted = [...units].sort((a, b) => a.startLine - b.startLine)
  /** @type {ParsedEditUnit[]} */
  const merged = []
  let cursor = 0

  for (const unit of sorted) {
    if (unit.startLine > cursor) {
      appendLineRangeUnits(lines, merged, cursor, unit.startLine - 1, protectedRanges)
    }
    merged.push(unit)
    cursor = Math.max(cursor, unit.endLine + 1)
  }

  if (cursor < lines.length) {
    appendLineRangeUnits(lines, merged, cursor, lines.length - 1, protectedRanges)
  }

  return merged
}

/**
 * @param {string[]} lines
 * @param {ParsedEditUnit[]} units
 * @param {number} start
 * @param {number} end
 * @param {[number, number][]} protectedRanges
 */
function appendLineRangeUnits(lines, units, start, end, protectedRanges) {
  let index = start

  while (index <= end) {
    if (isLineProtected(index, protectedRanges)) {
      index++
      continue
    }

    if (lines[index]?.trim() === '') {
      index++
      continue
    }

    const blockStart = index
    while (index <= end && lines[index]?.trim() !== '') {
      if (isLineProtected(index, protectedRanges)) break
      index++
    }

    const blockEnd = index - 1
    if (blockEnd >= blockStart) {
      units.push({
        adoc: lines.slice(blockStart, blockEnd + 1).join('\n'),
        startLine: blockStart,
        endLine: blockEnd,
      })
    }
  }
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
