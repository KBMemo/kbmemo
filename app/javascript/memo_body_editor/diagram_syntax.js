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
  const re = new RegExp(DIAGRAM_MACRO_RE.source, 'g')
  for (const match of text.matchAll(re)) {
    const full = match[0]
    results.push({
      from: lineFrom + match.index,
      to: lineFrom + match.index + full.length,
      macroPath: match[1].trim(),
      block: false,
    })
  }
  return results
}

/** diagram::flow.mmd[] → diagrams/flow.svg */
export function diagramSvgRelativePath(macroPath) {
  let path = macroPath.trim()
  if (!path) return null
  if (!path.startsWith('diagrams/')) path = `diagrams/${path}`
  const extMatch = path.match(/(\.[^./]+)$/i)
  if (!extMatch) return null
  return path.replace(new RegExp(`${extMatch[1].replace('.', '\\.')}$`, 'i'), '.svg')
}

/** diagram::flow.mmd[] → diagrams/flow.mmd */
export function diagramSourceRelativePath(macroPath) {
  let path = macroPath.trim()
  if (!path) return null
  if (!path.startsWith('diagrams/')) path = `diagrams/${path}`
  return path
}

/** diagrams/flow.svg → flow.mmd（ソース拡張子は推定） */
export function diagramMacroPathFromSvgRelative(svgRelative) {
  const match = svgRelative.match(/^diagrams\/(.+)\.svg$/i)
  if (!match) return null
  return `${match[1]}.mmd`
}

/** 編集ページ URL の diagram_key（diagrams/ なし） */
export function diagramDiagramKey(macroPath) {
  if (!macroPath?.trim()) return null
  return macroPath.trim().replace(/^diagrams\//, '')
}

export function diagramEditUrl(memoId, macroPath) {
  const key = diagramDiagramKey(macroPath)
  if (!memoId || !key) return null
  return `/memos/${encodeURIComponent(String(memoId))}/diagrams/${encodeURIComponent(key)}/edit`
}

/** ソースをシンタックスハイライト付きで表示するビューア */
export function diagramSourceUrl(memoId, macroPath) {
  const key = diagramDiagramKey(macroPath)
  if (!memoId || !key) return null
  return `/memos/${encodeURIComponent(String(memoId))}/diagrams/${encodeURIComponent(key)}/source`
}

/** SVG を拡大縮小できる別ウィンドウ用ビューア */
export function diagramViewUrl(memoId, macroPath) {
  const key = diagramDiagramKey(macroPath)
  if (!memoId || !key) return null
  return `/memos/${encodeURIComponent(String(memoId))}/diagrams/${encodeURIComponent(key)}/view`
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
