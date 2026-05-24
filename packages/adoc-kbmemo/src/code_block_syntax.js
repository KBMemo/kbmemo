/** Markdown フェンス（補助・非 AsciiDoc 正規） */
export const FENCE_OPEN = /^```([\w+#.-]*)?\s*$/
export const FENCE_CLOSE = /^```\s*$/

/** AsciiDoc listing / literal 区切り（https://docs.asciidoctor.org/asciidoc/latest/syntax-quick-reference/） */
export const LISTING_DELIM = /^-{4,}\s*$/
export const LITERAL_DELIM = /^\.{4,}\s*$/

/** ブロックタイトル（`.Some Ruby code` — 行頭 `.` の直後は空白不可） */
export const BLOCK_TITLE_LINE = /^\.([^\s].*)$/

/** `[source,ruby]` または `[source, ruby, opts]` */
export const SOURCE_ATTR_LINE = /^\[source,([^\],]+)(?:,[^\]]*)?\]\s*$/i

export function isFenceDelimiterLine(text) {
  return FENCE_OPEN.test(text) || FENCE_CLOSE.test(text)
}

function parseListingPreamble(doc, delimLineNo) {
  let language = ""
  let title = ""
  let titleLine = null
  let attrLine = null
  let lineNo = delimLineNo - 1

  while (lineNo >= 1) {
    const trimmed = doc.line(lineNo).text.trim()
    if (!trimmed) break

    const sourceMatch = trimmed.match(SOURCE_ATTR_LINE)
    if (sourceMatch) {
      language = sourceMatch[1].trim().toLowerCase()
      attrLine = lineNo
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

  const preambleLines = [titleLine, attrLine].filter((n) => n != null)
  const startLine = preambleLines.length > 0 ? Math.min(...preambleLines) : delimLineNo

  return { language, title, titleLine, attrLine, startLine }
}

function scanListingBlock(doc, lineNo) {
  const preamble = parseListingPreamble(doc, lineNo)
  const block = {
    kind: preamble.language || preamble.attrLine ? "source" : "listing",
    language: preamble.language,
    title: preamble.title,
    titleLine: preamble.titleLine,
    attrLine: preamble.attrLine,
    startLine: preamble.startLine,
    endLine: lineNo,
    openLine: lineNo,
    closeLine: null
  }
  lineNo++
  while (lineNo <= doc.lines) {
    const nextTrimmed = doc.line(lineNo).text.trim()
    if (LISTING_DELIM.test(nextTrimmed)) {
      block.endLine = lineNo
      block.closeLine = lineNo
      return { block, nextLine: lineNo + 1 }
    }
    block.endLine = lineNo
    lineNo++
  }
  return { block, nextLine: lineNo }
}

/**
 * コードブロック一覧。
 * AsciiDoc 正規: `.title` + `[source,lang]` + `----` … `----`
 * 補助: Markdown ``` フェンス、literal `....`
 */
export function scanCodeBlocks(doc) {
  const blocks = []
  let lineNo = 1

  while (lineNo <= doc.lines) {
    const text = doc.line(lineNo).text
    const trimmed = text.trim()

    const fenceOpen = text.match(FENCE_OPEN)
    if (fenceOpen) {
      const block = {
        kind: "fence",
        language: fenceOpen[1] || "",
        title: "",
        titleLine: null,
        attrLine: null,
        startLine: lineNo,
        endLine: lineNo,
        openLine: lineNo,
        closeLine: null
      }
      lineNo++
      while (lineNo <= doc.lines) {
        const next = doc.line(lineNo).text
        if (FENCE_CLOSE.test(next)) {
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
      continue
    }

    if (LISTING_DELIM.test(trimmed)) {
      const { block, nextLine } = scanListingBlock(doc, lineNo)
      blocks.push(block)
      lineNo = nextLine
      continue
    }

    if (LITERAL_DELIM.test(trimmed)) {
      const block = {
        kind: "literal",
        language: "",
        title: "",
        titleLine: null,
        attrLine: null,
        startLine: lineNo,
        endLine: lineNo,
        openLine: lineNo,
        closeLine: null
      }
      lineNo++
      while (lineNo <= doc.lines) {
        const nextTrimmed = doc.line(lineNo).text.trim()
        if (LITERAL_DELIM.test(nextTrimmed)) {
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
      continue
    }

    lineNo++
  }

  return blocks
}

export function codeBlockByLine(blocks) {
  const map = new Map()
  for (const block of blocks) {
    for (let n = block.startLine; n <= block.endLine; n++) {
      map.set(n, block)
    }
  }
  return map
}
