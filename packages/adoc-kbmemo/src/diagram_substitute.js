import { diagramSvgRelativePath } from './diagram_syntax.js'

const FENCE_LINE = /^```/
const BLOCK_DIAGRAM_LINE = /^(\s*)diagram::([^\[\]]+?)(\[[^\]]*\])?\s*$/
const DIAGRAM_MACRO_RE = /diagram::([^\[\]]+?)(\[[^\]]*\])?/g

/**
 * @param {string} text
 */
function escapeAsciidocUnquoted(text) {
  return text.replace(/#/g, '\\#')
}

/**
 * MemoDiagramMacro と同様に diagram:: を image:: SVG へ展開する（DB 上のソースは変更しない）。
 *
 * @param {string} macroPath
 */
function replaceDiagramMacro(macroPath) {
  const svgRel = diagramSvgRelativePath(macroPath)
  if (!svgRel) {
    return `[.memo-diagram-missing]#${escapeAsciidocUnquoted(macroPath)}#`
  }
  return `image::${svgRel}[opts=interactive]`
}

/**
 * @param {string} source
 */
export function substituteDiagramsForPreview(source) {
  if (!source) return source

  let inFenced = false
  return source
    .split('\n')
    .map((line) => {
      if (FENCE_LINE.test(line)) {
        inFenced = !inFenced
        return line
      }
      if (inFenced) return line

      const blockMatch = line.match(BLOCK_DIAGRAM_LINE)
      if (blockMatch) {
        return replaceDiagramMacro(blockMatch[2].trim())
      }

      return line.replace(DIAGRAM_MACRO_RE, (_, path) => replaceDiagramMacro(path.trim()))
    })
    .join('\n')
}
