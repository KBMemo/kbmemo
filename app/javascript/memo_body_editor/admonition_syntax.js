/** 行頭ラベル形式（NOTE: / TIP: / …） */
export const ADMONITION_LABEL =
  /^(NOTE|TIP|IMPORTANT|WARNING|CAUTION):(\s*)(.*)$/

import { isFenceDelimiterLine, LISTING_DELIM, LITERAL_DELIM } from "./code_block_syntax"

const HEADING_LINE = /^={1,6}\s/

/** 軽量パーサ: 空行・見出し・フェンス・次の admonition でブロック終了（Asciidoctor 準拠） */
export function isAdmonitionBlockEnd(text) {
  if (!text.trim()) return true
  if (ADMONITION_LABEL.test(text)) return true
  if (HEADING_LINE.test(text)) return true
  if (isFenceDelimiterLine(text)) return true
  if (LISTING_DELIM.test(text.trim()) || LITERAL_DELIM.test(text.trim())) return true
  if (/^(-{4,}|\.{4,}|\*{4,}|_{4,}|={4,})$/.test(text.trim())) return true
  return false
}

export function parseAdmonitionLabelLine(text) {
  const match = text.match(ADMONITION_LABEL)
  if (!match) return null
  return {
    kind: match[1].toLowerCase(),
    labelLength: match[1].length + 1 + match[2].length
  }
}

/**
 * フェンス外の admonition ブロック一覧。
 * @returns {{ kind: string, startLine: number, endLine: number, labelLength: number }[]}
 */
export function scanAdmonitionBlocks(doc, codeByLine = null) {
  const blocks = []
  let lineNo = 1

  while (lineNo <= doc.lines) {
    if (codeByLine?.has(lineNo)) {
      lineNo++
      continue
    }

    const text = doc.line(lineNo).text

    const parsed = parseAdmonitionLabelLine(text)
    if (!parsed) {
      lineNo++
      continue
    }

    const startLine = lineNo
    const block = { kind: parsed.kind, startLine, endLine: startLine, labelLength: parsed.labelLength }
    lineNo++

    while (lineNo <= doc.lines) {
      if (codeByLine?.has(lineNo)) break
      const nextText = doc.line(lineNo).text
      if (isAdmonitionBlockEnd(nextText)) break
      block.endLine = lineNo
      lineNo++
    }

    blocks.push(block)
  }

  return blocks
}

export function admonitionBlockByLine(blocks) {
  const map = new Map()
  for (const block of blocks) {
    for (let n = block.startLine; n <= block.endLine; n++) {
      map.set(n, block)
    }
  }
  return map
}
