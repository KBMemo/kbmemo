/** AsciiDoc stem / latexmath（表示は KaTeX、:stem: latexmath 想定） */

import { BLOCK_TITLE_LINE } from "./code_block_syntax"

const INLINE_STEM = /stem:\[([^\]]+)\]/g
const INLINE_LATEXMATH = /latexmath:\[([^\]]+)\]/g
const BLOCK_STEM_OPEN = /^\[(stem|latexmath)\]\s*$/i
const PASSTHROUGH_DELIM = /^\+{4,}\s*$/

/** 閉じ ++++ が無いブロックがメモ末尾まで伸びないよう上限 */
const MAX_STEM_BLOCK_BODY_LINES = 128

export function scanInlineMathMacrosOnLine(text, lineFrom) {
  const results = []
  for (const [re, kind] of [
    [INLINE_STEM, "stem"],
    [INLINE_LATEXMATH, "latexmath"]
  ]) {
    const matcher = new RegExp(re.source, "g")
    for (const match of text.matchAll(matcher)) {
      const full = match[0]
      results.push({
        from: lineFrom + match.index,
        to: lineFrom + match.index + full.length,
        latex: match[1],
        kind,
        display: false
      })
    }
  }
  return results
}

export function mathExclusionRanges(text, lineFrom) {
  return scanInlineMathMacrosOnLine(text, lineFrom).map((m) => [m.from, m.to])
}

/** `.Title` 行（任意）の直後に `[stem]` / `[latexmath]` が続く preamble */
function parseStemPreamble(doc, attrLineNo) {
  let title = ""
  let titleLine = null
  const prev = attrLineNo - 1

  if (prev >= 1) {
    const trimmed = doc.line(prev).text.trim()
    const titleMatch = trimmed.match(BLOCK_TITLE_LINE)
    if (titleMatch) {
      title = titleMatch[1].trim()
      titleLine = prev
    }
  }

  return {
    title,
    titleLine,
    startLine: titleLine ?? attrLineNo,
    attrLine: attrLineNo
  }
}

function tryParseStemBlockAtAttrLine(doc, attrLineNo, skipLine) {
  if (skipLine?.(attrLineNo)) return null

  const openMatch = doc.line(attrLineNo).text.trim().match(BLOCK_STEM_OPEN)
  if (!openMatch) return null

  const kind = openMatch[1].toLowerCase()
  const preamble = parseStemPreamble(doc, attrLineNo)
  let cursor = attrLineNo + 1
  if (cursor > doc.lines) return null

  if (!PASSTHROUGH_DELIM.test(doc.line(cursor).text.trim())) return null
  cursor++

  const openDelimLine = attrLineNo + 1
  const contentStartLine = cursor
  while (cursor <= doc.lines) {
    const bodyLines = cursor - contentStartLine
    if (bodyLines > MAX_STEM_BLOCK_BODY_LINES) break
    const trimmed = doc.line(cursor).text.trim()
    if (PASSTHROUGH_DELIM.test(trimmed)) break
    if (BLOCK_STEM_OPEN.test(trimmed)) break
    if (BLOCK_TITLE_LINE.test(trimmed)) break
    cursor++
  }

  if (cursor > doc.lines || !PASSTHROUGH_DELIM.test(doc.line(cursor).text.trim())) {
    return null
  }

  const contentEndLine = cursor - 1
  const latex = extractBlockLatex(doc, contentStartLine, contentEndLine)
  if (contentEndLine < contentStartLine || !latex.trim()) return null

  return {
    ...preamble,
    endLine: cursor,
    closeDelimLine: cursor,
    openDelimLine,
    contentStartLine,
    contentEndLine,
    kind,
    latex,
    display: true
  }
}

/**
 * `.title`（任意）+ [stem] / [latexmath] + ++++ … ++++ ブロック。
 * @param {import("@codemirror/state").Text} doc
 */
export function scanStemBlocks(doc, skipLine) {
  const blocks = []
  let lineNo = 1

  while (lineNo <= doc.lines) {
    if (skipLine?.(lineNo)) {
      lineNo++
      continue
    }

    const block = tryParseStemBlockAtAttrLine(doc, lineNo, skipLine)
    if (block) {
      blocks.push(block)
      lineNo = block.endLine + 1
      continue
    }

    lineNo++
  }

  return blocks
}

function extractBlockLatex(doc, startLine, endLine) {
  if (endLine < startLine) return ""
  const parts = []
  for (let n = startLine; n <= endLine; n++) {
    parts.push(doc.line(n).text)
  }
  return parts.join("\n").trim()
}

/**
 * 閉じ ++++ が無い（または未確定の）[stem] ブロックに含まれる行。
 * 装飾で置き換えず編集可能に保つ。
 */
export function scanStemDraftLineSet(doc, skipLine) {
  const lines = new Set()
  let lineNo = 1

  while (lineNo <= doc.lines) {
    if (skipLine?.(lineNo)) {
      lineNo++
      continue
    }

    const trimmed = doc.line(lineNo).text.trim()
    const openMatch = trimmed.match(BLOCK_STEM_OPEN)
    if (!openMatch) {
      lineNo++
      continue
    }

    const { startLine: draftStart } = parseStemPreamble(doc, lineNo)
    let cursor = lineNo + 1
    if (cursor > doc.lines) {
      lines.add(draftStart)
      break
    }

    if (!PASSTHROUGH_DELIM.test(doc.line(cursor).text.trim())) {
      lines.add(draftStart)
      lineNo++
      continue
    }

    cursor++
    const contentStartLine = cursor
    let foundClose = false

    while (cursor <= doc.lines) {
      const bodyLines = cursor - contentStartLine
      if (bodyLines > MAX_STEM_BLOCK_BODY_LINES) break
      const lineTrimmed = doc.line(cursor).text.trim()
      if (PASSTHROUGH_DELIM.test(lineTrimmed)) {
        foundClose = true
        break
      }
      if (BLOCK_STEM_OPEN.test(lineTrimmed)) break
      if (BLOCK_TITLE_LINE.test(lineTrimmed)) break
      cursor++
    }

    if (!foundClose) {
      const draftEnd = Math.min(cursor, doc.lines)
      for (let n = draftStart; n <= draftEnd; n++) lines.add(n)
      lineNo = draftEnd + 1
      continue
    }

    lineNo = cursor + 1
  }

  return lines
}

export function stemBlockByLine(blocks) {
  const map = new Map()
  for (const block of blocks) {
    for (let n = block.startLine; n <= block.endLine; n++) {
      map.set(n, block)
    }
  }
  return map
}

export function cursorInStemBlock(state, block) {
  return state.selection.ranges.some((range) => {
    const lineNo = state.doc.lineAt(range.head).number
    return lineNo >= block.startLine && lineNo <= block.endLine
  })
}

export function selectionHeadInStemBlock(state, block) {
  const lineNo = state.doc.lineAt(state.selection.main.head).number
  return lineNo >= block.startLine && lineNo <= block.endLine
}

export function stemFirstEditLine(block) {
  return block.contentStartLine
}

/** タイトル行・属性行はクリックで raw 編集へ */
export function isStemPreambleLine(lineNo, block) {
  return lineNo === block.attrLine || lineNo === block.titleLine
}

export function stemBlockAtLine(state, lineNo, skipLine) {
  for (const block of scanStemBlocks(state.doc, skipLine)) {
    if (lineNo >= block.startLine && lineNo <= block.endLine) return block
  }
  return null
}

export function stemBlockAtCoords(view, clientX, clientY, skipLine) {
  const rect = view.scrollDOM.getBoundingClientRect()
  const docY = clientY - rect.top + view.scrollDOM.scrollTop

  for (const block of scanStemBlocks(view.state.doc, skipLine)) {
    try {
      const top = view.lineBlockAt(block.startLine).top
      let bottom = top
      for (let n = block.startLine; n <= block.endLine; n++) {
        const lb = view.lineBlockAt(n)
        bottom = Math.max(bottom, lb.top + lb.height)
      }
      if (docY >= top - 1 && docY <= bottom + 1) return block
    } catch {
      continue
    }
  }
  return null
}

export function stemBlockForArrowKey(state, key, skipLine) {
  const head = state.selection.main.head
  if (head < 0 || head > state.doc.length) return null

  const lineNo = state.doc.lineAt(head).number
  const down = key === "ArrowDown" || key === "ArrowRight"
  const up = key === "ArrowUp" || key === "ArrowLeft"
  if (!down && !up) return null

  for (const block of scanStemBlocks(state.doc, skipLine)) {
    if (down && lineNo < block.endLine && lineNo >= block.startLine - 1) {
      return block
    }
    if (up && lineNo === block.endLine + 1) {
      return block
    }
  }

  return null
}

/**
 * parseEditUnits 向け: `[stem]` + `++++` ブロックを 0-based 行範囲で返す。
 *
 * @param {string[]} lines
 * @param {(lineIndex: number) => boolean} [skipLine] 0-based
 * @returns {{ adoc: string, startLine: number, endLine: number }[]}
 */
export function extractStemBlockUnitsFromLines(lines, skipLine) {
  const doc = {
    lines: lines.length,
    line(lineNo) {
      return { text: lines[lineNo - 1] ?? '' }
    },
  }
  const skipLineOneBased = skipLine ? (lineNo) => skipLine(lineNo - 1) : undefined
  const blocks = scanStemBlocks(doc, skipLineOneBased)

  return blocks.map((block) => {
    const startLine = block.startLine - 1
    const endLine = block.endLine - 1
    return {
      adoc: lines.slice(startLine, endLine + 1).join('\n'),
      startLine,
      endLine,
    }
  })
}
