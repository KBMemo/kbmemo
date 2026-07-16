import { loadDocument } from './instance.js'
import { computeHighlights } from './highlight.js'
import { normalizeMemoImagePathsInSource } from '../../adoc-kbmemo/src/image_syntax.js'
import { restrictPassthroughInSource } from '../../adoc-kbmemo/src/passthrough_restrict.js'
import { diagramAvailabilityCacheKey, substituteDiagramsForPreview } from '../../adoc-kbmemo/src/diagram_substitute.js'
import { substituteTsuzuraForPreview, tsuzuraCacheKey } from '../../adoc-kbmemo/src/tsuzura_substitute.js'
import { substituteWikiLinksForPreview } from '../../adoc-kbmemo/src/wiki_link_substitute.js'

/** @typedef {{ from: number, to: number, className: string }} HighlightSpan */
/** @typedef {{ source: string, doc: import('@asciidoctor/core').Document, html: string | null, highlights: HighlightSpan[] }} ParseCache */

/** @type {ParseCache} */
let cache = { source: '', doc: null, html: null, highlights: [] }
/** @type {string | null | undefined} */
let cachePreviewMemoId
/** @type {string | undefined} */
let cachePreviewWikiLabelsKey
/** @type {string | undefined} */
let cachePreviewDiagramKey

/**
 * Parse for editor highlights (debounced via CodeMirror ViewPlugin).
 * Reuses cached doc when source is unchanged.
 *
 * @param {string} source
 * @returns {Promise<HighlightSpan[]>}
 */
export async function refreshHighlights(source) {
  if (cache.source === source) {
    return cache.highlights
  }

  const doc = await loadDocument(source)
  const highlights = await computeHighlights(source, doc)
  cache = { source, doc, highlights, html: null }
  cachePreviewMemoId = undefined
  cachePreviewWikiLabelsKey = undefined
  cachePreviewDiagramKey = undefined
  cachePreviewTsuzuraKey = undefined
  return highlights
}

/**
 * @param {string | null | undefined} memoId
 */
function previewConvertOptions(memoId) {
  /** @type {Record<string, unknown>} */
  const options = {
    safe: 'safe',
    attributes: {
      icons: 'font',
    },
  }
  if (memoId != null && memoId !== '') {
    options.attributes = {
      .../** @type {Record<string, string>} */ (options.attributes),
      imagesdir: `/memos/${encodeURIComponent(String(memoId))}/assets/`,
    }
  }
  return options
}

/**
 * @param {Map<string, { resolved?: boolean, memo_id?: number | null }> | undefined} wikiLabels
 */
function wikiLabelsCacheKey(wikiLabels) {
  if (!wikiLabels || wikiLabels.size === 0) return ''
  return [...wikiLabels.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, entry]) => `${key}\t${entry.resolved ? 1 : 0}\t${entry.memo_uid ?? ''}\t${entry.memo_id ?? ''}`)
    .join('\n')
}

/** @type {string | undefined} */
let cachePreviewTsuzuraKey

/**
 * @param {Map<string, boolean> | undefined} diagramAvailability
 * @param {{ urls?: Map<string, string>, albums?: Map<string, string[]> } | undefined} tsuzuraCache
 */
function previewSourceForConvert(source, memoId, wikiLabels, diagramAvailability, tsuzuraCache) {
  let processed = substituteDiagramsForPreview(source, diagramAvailability)
  if (wikiLabels !== undefined) {
    processed = substituteWikiLinksForPreview(processed, wikiLabels)
  }
  if (tsuzuraCache !== undefined) {
    processed = substituteTsuzuraForPreview(processed, tsuzuraCache)
  }
  if (memoId != null && memoId !== '') {
    processed = normalizeMemoImagePathsInSource(processed, memoId)
  }
  return restrictPassthroughInSource(processed)
}

/**
 * Parse for preview HTML (debounced).
 * Reuses doc/highlights from {@link refreshHighlights} when possible.
 *
 * @param {string} source
 * @param {{ memoId?: string | null, diagramAvailability?: Map<string, boolean>, wikiLabels?: Map<string, object>, tsuzuraCache?: { urls: Map<string, string>, albums: Map<string, string[]> } }} [options]
 * @returns {Promise<{ html: string, highlights: HighlightSpan[] }>}
 */
export async function refreshPreview(source, { memoId, diagramAvailability, wikiLabels, tsuzuraCache } = {}) {
  const diagramKey = diagramAvailability !== undefined ? diagramAvailabilityCacheKey(diagramAvailability) : undefined
  const labelsKey = wikiLabels !== undefined ? wikiLabelsCacheKey(wikiLabels) : undefined
  const tsuzuraKey = tsuzuraCache !== undefined ? tsuzuraCacheKey(tsuzuraCache) : undefined
  const previewSource = previewSourceForConvert(source, memoId, wikiLabels, diagramAvailability, tsuzuraCache)

  if (
    cache.source === source &&
    cache.html &&
    cachePreviewMemoId === memoId &&
    cachePreviewDiagramKey === diagramKey &&
    cachePreviewWikiLabelsKey === labelsKey &&
    cachePreviewTsuzuraKey === tsuzuraKey
  ) {
    return { html: cache.html, highlights: cache.highlights }
  }

  if (cache.source !== source || !cache.doc) {
    const doc = await loadDocument(source)
    const highlights = await computeHighlights(source, doc)
    cache = { source, doc, highlights, html: null }
    cachePreviewMemoId = undefined
    cachePreviewWikiLabelsKey = undefined
    cachePreviewDiagramKey = undefined
    cachePreviewTsuzuraKey = undefined
  }

  const previewDoc =
    previewSource === source ? cache.doc : await loadDocument(previewSource)
  cache.html = await previewDoc.convert(previewConvertOptions(memoId))
  cachePreviewMemoId = memoId
  cachePreviewDiagramKey = diagramKey
  cachePreviewWikiLabelsKey = labelsKey
  cachePreviewTsuzuraKey = tsuzuraKey
  return { html: cache.html, highlights: cache.highlights }
}

export function clearParseCache() {
  cache = { source: '', doc: null, html: null, highlights: [] }
  cachePreviewMemoId = undefined
  cachePreviewWikiLabelsKey = undefined
  cachePreviewDiagramKey = undefined
  cachePreviewTsuzuraKey = undefined
}
