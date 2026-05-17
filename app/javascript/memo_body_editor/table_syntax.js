import { BLOCK_TITLE_LINE, SOURCE_ATTR_LINE } from "./code_block_syntax"

/** AsciiDoc テーブル区切り（|===） */
export const TABLE_DELIM = /^\|={3,}\s*$/

/** テーブル属性行（[cols=…] / [options=header] 等。source は除外） */
export function isTableAttrLine(text) {
  const trimmed = text.trim()
  return /^\[[^\]]+\]\s*$/.test(trimmed) && !SOURCE_ATTR_LINE.test(trimmed)
}

export function isTableDelimiterLine(text) {
  return TABLE_DELIM.test(text.trim())
}

/** テーブル行（| で始まる。区切り行は除く） */
export function isTableRowLine(text) {
  const trimmed = text.trim()
  return trimmed.startsWith("|") && !TABLE_DELIM.test(trimmed)
}

/** ヘッダー行（セルが `<` で始まる AsciiDoc 記法） */
export function isTableHeaderRow(text) {
  return isTableRowLine(text) && /^\s*\|</.test(text)
}

function parseTablePreamble(doc, delimLineNo) {
  let title = ""
  let titleLine = null
  const attrLines = []
  let lineNo = delimLineNo - 1

  while (lineNo >= 1) {
    const trimmed = doc.line(lineNo).text.trim()
    if (!trimmed) break

    if (isTableAttrLine(trimmed)) {
      attrLines.push(lineNo)
      lineNo--
      continue
    }

    const titleMatch = trimmed.match(BLOCK_TITLE_LINE)
    if (titleMatch) {
      title = titleMatch[1].trim()
      titleLine = lineNo
      lineNo--
      continue
    }

    break
  }

  const preambleLines = [titleLine, ...attrLines].filter((n) => n != null)
  const startLine = preambleLines.length > 0 ? Math.min(...preambleLines) : delimLineNo

  return { title, titleLine, attrLines, startLine }
}

/**
 * |=== テーブルブロック（https://docs.asciidoctor.org/asciidoc/latest/syntax-quick-reference/）
 */
export function scanTableBlocks(doc, skipLine = () => false) {
  const blocks = []
  let lineNo = 1

  while (lineNo <= doc.lines) {
    if (skipLine(lineNo)) {
      lineNo++
      continue
    }

    const trimmed = doc.line(lineNo).text.trim()
    if (!TABLE_DELIM.test(trimmed)) {
      lineNo++
      continue
    }

    const preamble = parseTablePreamble(doc, lineNo)
    const block = {
      kind: "table",
      title: preamble.title,
      titleLine: preamble.titleLine,
      attrLines: preamble.attrLines,
      startLine: preamble.startLine,
      endLine: lineNo,
      openLine: lineNo,
      closeLine: null
    }
    lineNo++

    while (lineNo <= doc.lines) {
      if (skipLine(lineNo)) break
      const nextTrimmed = doc.line(lineNo).text.trim()
      if (TABLE_DELIM.test(nextTrimmed)) {
        block.endLine = lineNo
        block.closeLine = lineNo
        blocks.push(block)
        lineNo++
        break
      }
      block.endLine = lineNo
      lineNo++
    }

    if (block.closeLine == null) blocks.push(block)
  }

  return blocks
}

export function tableBlockByLine(blocks) {
  const map = new Map()
  for (const block of blocks) {
    for (let n = block.startLine; n <= block.endLine; n++) {
      map.set(n, block)
    }
  }
  return map
}

export function isTableBodyLine(lineNo, block) {
  return lineNo >= block.openLine && lineNo <= block.endLine
}
