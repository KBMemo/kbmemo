import { diagramSvgRelativePath } from './diagram_syntax.js'
import { memoAssetSrc } from './image_syntax.js'

const FENCE_LINE = /^```/
const BLOCK_DIAGRAM_LINE = /^(\s*)diagram::([^\[\]]+?)(\[[^\]]*\])?\s*$/
const DIAGRAM_MACRO_RE = /diagram::([^\[\]]+)(\[[^\]]*\])?/g

/**
 * @param {string} text
 */
function escapeAsciidocUnquoted(text) {
  return text.replace(/#/g, '\\#')
}

/**
 * @param {string} macroPath
 * @param {Map<string, boolean> | undefined} availability
 */
function replaceDiagramMacroWithAvailability(macroPath, availability) {
  const svgRel = diagramSvgRelativePath(macroPath)
  if (!svgRel) {
    return `[.memo-diagram-missing]#${escapeAsciidocUnquoted(macroPath)}#`
  }
  if (availability && availability.get(svgRel) !== true) {
    return `[.memo-diagram-missing]#${escapeAsciidocUnquoted(svgRel)}#`
  }
  return `image::${svgRel}[]`
}

/**
 * @param {string} source
 */
export function substituteDiagramsForPreview(source, availability) {
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
        return replaceDiagramMacroWithAvailability(blockMatch[2].trim(), availability)
      }

      return line.replace(DIAGRAM_MACRO_RE, (_, path) =>
        replaceDiagramMacroWithAvailability(path.trim(), availability),
      )
    })
    .join('\n')
}

export function extractDiagramSvgRelativePaths(source) {
  if (!source) return []

  const paths = new Set()
  let inFenced = false
  for (const line of source.split('\n')) {
    if (FENCE_LINE.test(line)) {
      inFenced = !inFenced
      continue
    }
    if (inFenced) continue

    const blockMatch = line.match(BLOCK_DIAGRAM_LINE)
    if (blockMatch) {
      const svgRel = diagramSvgRelativePath(blockMatch[2].trim())
      if (svgRel) paths.add(svgRel)
      continue
    }

    for (const match of line.matchAll(DIAGRAM_MACRO_RE)) {
      const svgRel = diagramSvgRelativePath(match[1].trim())
      if (svgRel) paths.add(svgRel)
    }
  }
  return [...paths]
}

/**
 * @param {Map<string, boolean>} cache
 * @param {string | number | null | undefined} memoId
 * @param {string} source
 */
export async function ensureDiagramSvgsInCache(cache, memoId, source) {
  if (!memoId) return

  const missing = extractDiagramSvgRelativePaths(source).filter((path) => !cache.has(path))
  if (missing.length === 0) return

  await Promise.all(
    missing.map(async (path) => {
      const url = memoAssetSrc(memoId, path)
      if (!url) {
        cache.set(path, false)
        return
      }
      try {
        const response = await fetch(url, {
          method: 'HEAD',
          credentials: 'same-origin',
          cache: 'no-store',
        })
        cache.set(path, response.ok)
      } catch {
        cache.set(path, false)
      }
    }),
  )
}

export function diagramAvailabilityCacheKey(availability) {
  if (!availability || availability.size === 0) return ''
  return [...availability.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([path, available]) => `${path}\t${available ? 1 : 0}`)
    .join('\n')
}
