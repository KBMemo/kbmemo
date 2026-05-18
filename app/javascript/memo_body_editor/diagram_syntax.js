/** AsciiDoc `diagram::` マクロ（MemoDiagram / MemoDiagramMacro と同じ規則） */

const BLOCK_DIAGRAM_LINE = /^(\s*)diagram::([^\[\]]+?)(\[[^\]]*\])?\s*$/
const DIAGRAM_MACRO_RE = /diagram::([^\[\]]+?)(\[[^\]]*\])?/g

export function parseBlockDiagramLine(text) {
  const match = text.match(BLOCK_DIAGRAM_LINE)
  if (!match) return null
  return { macroPath: match[2].trim(), indentLength: match[1].length }
}

export function scanDiagramMacrosOnLine(text, lineFrom) {
  const results = []
  const re = new RegExp(DIAGRAM_MACRO_RE.source, "g")
  for (const match of text.matchAll(re)) {
    const full = match[0]
    results.push({
      from: lineFrom + match.index,
      to: lineFrom + match.index + full.length,
      macroPath: match[1].trim(),
      block: false
    })
  }
  return results
}

/** diagram::flow.mmd[] → diagrams/flow.svg */
export function diagramSvgRelativePath(macroPath) {
  let path = macroPath.trim()
  if (!path) return null
  if (!path.startsWith("diagrams/")) path = `diagrams/${path}`
  const extMatch = path.match(/(\.[^./]+)$/i)
  if (!extMatch) return null
  return path.replace(new RegExp(`${extMatch[1].replace(".", "\\.")}$`, "i"), ".svg")
}

/** 編集ページ URL の diagram_key（diagrams/ なし） */
export function diagramEditUrl(memoId, macroPath) {
  if (!memoId || !macroPath?.trim()) return null
  const key = macroPath.trim().replace(/^diagrams\//, "")
  return `/memos/${encodeURIComponent(String(memoId))}/diagrams/${encodeURIComponent(key)}/edit`
}

export function diagramExclusionRanges(text, lineFrom) {
  return scanDiagramMacrosOnLine(text, lineFrom).map((m) => [m.from, m.to])
}

export function diagramBlockLineSet(doc, skipLine) {
  const lines = new Set()
  for (let lineNo = 1; lineNo <= doc.lines; lineNo++) {
    if (skipLine?.(lineNo)) continue
    if (parseBlockDiagramLine(doc.line(lineNo).text)) lines.add(lineNo)
  }
  return lines
}
