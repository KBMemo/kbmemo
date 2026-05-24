import { BLOCK_TITLE_LINE, codeBlockByLine, scanCodeBlocks, SOURCE_ATTR_LINE } from "./code_block_syntax"

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

/** 行テキストからセル内容の配列（表示用） */
export function parseTableRowCells(text) {
  const trimmed = text.trim()
  if (!isTableRowLine(text)) return []

  return trimmed
    .slice(1)
    .split("|")
    .map((part) => formatTableCellDisplay(part.trim()))
}

/** セル先頭の AsciiDoc 修飾（< . ^ 等）を除いた表示文字列 */
export function formatTableCellDisplay(raw) {
  if (!raw) return ""

  let cell = raw.replace(/^[<.^:]+/, "")
  cell = cell.replace(/\d[\+*]$/, "")
  return cell.trim()
}

function countColsSpec(spec) {
  const part = spec.split("*")[0]
  const parts = part.split(",").map((s) => s.trim()).filter(Boolean)
  return Math.max(parts.length, 1)
}

/** [cols="2,3"] / [cols=2*] などから列数 */
export function parseTableColCount(doc, attrLines) {
  for (const lineNo of attrLines) {
    const trimmed = doc.line(lineNo).text.trim()
    const quoted = trimmed.match(/^\[cols=["']([^"']+)["']/)
    if (quoted) return countColsSpec(quoted[1])

    const bare = trimmed.match(/^\[cols=([^\]]+)\]/)
    if (bare) return countColsSpec(bare[1])
  }
  return null
}

export function tableHasHeaderOption(doc, attrLines) {
  for (const lineNo of attrLines) {
    const t = doc.line(lineNo).text
    if (/options=header|%header/i.test(t)) return true
  }
  return false
}

/** [cols="2,3"] などから grid-template-columns 用の fr 配列 */
export function parseTableColsFr(doc, attrLineNumbers) {
  for (const lineNo of attrLineNumbers) {
    const trimmed = doc.line(lineNo).text.trim()
    const match = trimmed.match(/^\[cols=["']([^"']+)["']/)
    if (!match) continue

    return match[1].split(",").map((part) => {
      const num = part.trim().match(/^(\d+(?:\.\d+)?)/)
      return num ? `minmax(0, ${num[1]}fr)` : "minmax(0, 1fr)"
    })
  }
  return null
}

export function inferTableColCount(doc, block) {
  const fromAttr = parseTableColCount(doc, block.attrLines)
  if (fromAttr) return fromAttr

  const bodyStart = block.openLine + 1
  const bodyEnd = block.closeLine != null ? block.closeLine - 1 : block.endLine
  for (let lineNo = bodyStart; lineNo <= bodyEnd; lineNo++) {
    const text = doc.line(lineNo).text
    if (!text.trim()) continue
    if (isTableRowLine(text)) {
      const cells = parseTableRowCells(text)
      return Math.max(cells.length, 1)
    }
  }
  return 1
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
      colsFr: parseTableColsFr(doc, preamble.attrLines),
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

/** 選択範囲がテーブルブロックと重なるか */
export function selectionInTableBlock(state, block) {
  const from = state.doc.line(block.startLine).from
  const to = state.doc.line(block.endLine).to
  return state.selection.ranges.some((range) => range.from <= to && range.to >= from)
}

/** カーソル移動で raw に入る行（タイトル行・|=== 先頭の Table 行） */
export function isTablePreambleRawLine(lineNo, block) {
  if (lineNo === block.openLine) return true
  if (block.titleLine != null && lineNo === block.titleLine) return true
  return false
}

/** 主カーソル（head）がテーブルブロック内の行にあるか */
export function selectionHeadInTableBlock(state, block) {
  const head = state.selection.main.head
  if (head < 0 || head > state.doc.length) return false
  const lineNo = state.doc.lineAt(head).number
  return lineNo >= block.startLine && lineNo <= block.endLine
}

export function allTableBlocks(state) {
  const codeBlocks = scanCodeBlocks(state.doc)
  const codeByLine = codeBlockByLine(codeBlocks)
  return scanTableBlocks(state.doc, (n) => codeByLine.has(n))
}

export function tableBlockAtLine(state, lineNo) {
  return tableBlockByLine(allTableBlocks(state)).get(lineNo) ?? null
}

/** クリック座標が表ブロックの表示領域内か（block replace でも判定） */
export function tableBlockAtCoords(view, clientX, clientY) {
  const rect = view.scrollDOM.getBoundingClientRect()
  const docY = clientY - rect.top + view.scrollDOM.scrollTop

  for (const block of allTableBlocks(view.state)) {
    try {
      const top = view.lineBlockAt(block.startLine).top
      let bottom = top
      for (let lineNo = block.startLine; lineNo <= block.endLine; lineNo++) {
        const lb = view.lineBlockAt(lineNo)
        bottom = Math.max(bottom, lb.top + lb.height)
      }
      if (docY >= top - 1 && docY <= bottom + 1) return block
    } catch {
      continue
    }
  }
  return null
}

/** ビュー座標の Y からドキュメント行番号（block replace / ウィジェット上でも可） */
export function tableLineFromViewY(view, clientY) {
  const rect = view.scrollDOM.getBoundingClientRect()
  const docY = clientY - rect.top + view.scrollDOM.scrollTop
  const lb = view.lineBlockAtHeight(docY)
  return view.state.doc.lineAt(lb.from).number
}

/**
 * プレビュー中に矢印で表へ入る意図があるか（行本体は block replace で通過不能なため raw へ）。
 */
export function tableBlockForArrowKey(state, key) {
  const head = state.selection.main.head
  if (head < 0 || head > state.doc.length) return null

  const lineNo = state.doc.lineAt(head).number
  const down = key === "ArrowDown" || key === "ArrowRight"
  const up = key === "ArrowUp" || key === "ArrowLeft"
  if (!down && !up) return null

  for (const block of allTableBlocks(state)) {
    if (down && tableBlockAtLine(state, lineNo) === block && lineNo === block.openLine) {
      return block
    }

    if (up && lineNo === block.endLine + 1) {
      return block
    }
  }

  return null
}

/** クリック Y に最も近い表内の行番号 */
export function nearestTableLineInBlock(view, clientY, block) {
  const rect = view.scrollDOM.getBoundingClientRect()
  const docY = clientY - rect.top + view.scrollDOM.scrollTop
  let bestLine = tableFirstEditLine(view.state.doc, block)
  let bestDist = Infinity

  for (let lineNo = block.startLine; lineNo <= block.endLine; lineNo++) {
    try {
      const lb = view.lineBlockAt(lineNo)
      const mid = lb.top + lb.height / 2
      const dist = Math.abs(docY - mid)
      if (dist < bestDist) {
        bestDist = dist
        bestLine = lineNo
      }
    } catch {
      continue
    }
  }
  return bestLine
}

export function tableBlockAtSelection(state) {
  const head = state.selection.main.head
  if (head < 0 || head > state.doc.length) return null
  try {
    return tableBlockAtLine(state, state.doc.lineAt(head).number)
  } catch {
    return null
  }
}

/** 編集用にカーソルを置く最初のセル行（|=== の次の行） */
export function tableFirstEditLine(doc, block) {
  const end = block.closeLine != null ? block.closeLine - 1 : block.endLine
  for (let lineNo = block.openLine + 1; lineNo <= end; lineNo++) {
    if (isTableRowLine(doc.line(lineNo).text)) return lineNo
  }
  return block.openLine + 1 <= end ? block.openLine + 1 : block.openLine
}

/**
 * テーブル本文をセクション（空行区切り）に分け、論理行（N 列）にまとめる。
 * 1行1セル形式と |A |B の1行複数セル形式の両方に対応。
 */
export function groupTableLogicalRows(doc, block) {
  const ncol = inferTableColCount(doc, block)
  const explicitHeader = tableHasHeaderOption(doc, block.attrLines)
  const bodyStart = block.openLine + 1
  const bodyEnd = block.closeLine != null ? block.closeLine - 1 : block.endLine

  const sections = []
  let currentCells = []
  const gapLines = []

  const flushSection = () => {
    if (currentCells.length > 0) {
      sections.push(currentCells)
      currentCells = []
    }
  }

  for (let lineNo = bodyStart; lineNo <= bodyEnd; lineNo++) {
    const text = doc.line(lineNo).text
    const trimmed = text.trim()

    if (!trimmed) {
      flushSection()
      gapLines.push(lineNo)
      continue
    }

    if (isTableRowLine(text)) {
      const cells = parseTableRowCells(text)
      for (const cell of cells) {
        currentCells.push({ lineNo, cell })
      }
    }
  }
  flushSection()

  const logicalRows = []
  const useAutoHeader = !explicitHeader && sections.length > 1

  sections.forEach((section, sectionIndex) => {
    const isHeaderSection = explicitHeader ? sectionIndex === 0 : useAutoHeader && sectionIndex === 0

    let buffer = []
    let startLine = null
    let endLine = null

    const emitRow = () => {
      if (buffer.length === 0) return
      logicalRows.push({
        kind: "row",
        cells: [...buffer],
        startLine,
        endLine,
        isHeader: isHeaderSection
      })
      buffer = []
      startLine = null
      endLine = null
    }

    for (const { lineNo, cell } of section) {
      if (buffer.length === 0) startLine = lineNo
      buffer.push(cell)
      endLine = lineNo
      if (buffer.length >= ncol) {
        emitRow()
      }
    }
    if (buffer.length > 0) emitRow()
  })

  for (const lineNo of gapLines) {
    logicalRows.push({ kind: "gap", lineNo })
  }

  logicalRows.sort((a, b) => {
    const lineA = a.kind === "gap" ? a.lineNo : a.startLine
    const lineB = b.kind === "gap" ? b.lineNo : b.startLine
    return lineA - lineB
  })

  return logicalRows
}
