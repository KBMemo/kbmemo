/** 行頭ラベル形式（NOTE: / TIP: / …） */
export const ADMONITION_LABEL =
  /^(NOTE|TIP|IMPORTANT|WARNING|CAUTION):(\s*)(.*)$/

const FENCE_LINE = /^```/
const HEADING_LINE = /^={1,6}\s/

/** 軽量パーサ: 空行・見出し・フェンス・次の admonition でブロック終了（Asciidoctor 準拠） */
export function isAdmonitionBlockEnd(text) {
  if (!text.trim()) return true
  if (ADMONITION_LABEL.test(text)) return true
  if (HEADING_LINE.test(text)) return true
  if (FENCE_LINE.test(text)) return true
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
export function scanAdmonitionBlocks(doc) {
  const blocks = []
  let inFenced = false
  let lineNo = 1

  while (lineNo <= doc.lines) {
    const text = doc.line(lineNo).text

    if (FENCE_LINE.test(text)) {
      inFenced = !inFenced
      lineNo++
      continue
    }
    if (inFenced) {
      lineNo++
      continue
    }

    const parsed = parseAdmonitionLabelLine(text)
    if (!parsed) {
      lineNo++
      continue
    }

    const startLine = lineNo
    const block = { kind: parsed.kind, startLine, endLine: startLine, labelLength: parsed.labelLength }
    lineNo++

    while (lineNo <= doc.lines) {
      const nextText = doc.line(lineNo).text
      if (FENCE_LINE.test(nextText)) break
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
