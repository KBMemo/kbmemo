import { loadDocument } from './instance.js'
import { computeHighlights } from './highlight.js'
import { substituteDiagramsForPreview } from '@kbmemo/memo-body-editor/diagram_substitute.js'
import { normalizeMemoImagePathsInSource } from '@kbmemo/memo-body-editor/image_syntax.js'

/** @typedef {{ from: number, to: number, className: string }} HighlightSpan */
/** @typedef {{ source: string, doc: import('@asciidoctor/core').Document, html: string | null, highlights: HighlightSpan[] }} ParseCache */

/** @type {ParseCache} */
let cache = { source: '', doc: null, html: null, highlights: [] }
/** @type {string | null | undefined} */
let cachePreviewMemoId

/**
 * Parse for editor highlights (sync on every keystroke).
 * Reuses cached doc when source is unchanged.
 *
 * @param {string} source
 * @returns {HighlightSpan[]}
 */
export function refreshHighlights(source) {
  if (cache.source === source) {
    return cache.highlights
  }

  const doc = loadDocument(source)
  const highlights = computeHighlights(source, doc)
  cache = { source, doc, highlights, html: null }
  cachePreviewMemoId = undefined
  return highlights
}

/**
 * @param {string | null | undefined} memoId
 */
function previewConvertOptions(memoId) {
  /** @type {Record<string, unknown>} */
  const options = { safe: 'safe' }
  if (memoId != null && memoId !== '') {
    options.attributes = {
      imagesdir: `/memos/${encodeURIComponent(String(memoId))}/assets/`,
    }
  }
  return options
}

/**
 * @param {string} source
 * @param {string | null | undefined} memoId
 */
function previewSourceForConvert(source, memoId) {
  let processed = substituteDiagramsForPreview(source)
  if (memoId != null && memoId !== '') {
    processed = normalizeMemoImagePathsInSource(processed, memoId)
  }
  return processed
}

/**
 * Parse for preview HTML (debounced).
 * Reuses doc/highlights from {@link refreshHighlights} when possible.
 *
 * @param {string} source
 * @param {{ memoId?: string | null }} [options]
 */
export function refreshPreview(source, { memoId } = {}) {
  const previewSource = previewSourceForConvert(source, memoId)

  if (cache.source === source && cache.html && cachePreviewMemoId === memoId) {
    return { html: cache.html, highlights: cache.highlights }
  }

  if (cache.source !== source || !cache.doc) {
    const doc = loadDocument(source)
    const highlights = computeHighlights(source, doc)
    cache = { source, doc, highlights, html: null }
    cachePreviewMemoId = undefined
  }

  const previewDoc =
    previewSource === source ? cache.doc : loadDocument(previewSource)
  cache.html = previewDoc.convert(previewConvertOptions(memoId))
  cachePreviewMemoId = memoId
  return { html: cache.html, highlights: cache.highlights }
}

export function clearParseCache() {
  cache = { source: '', doc: null, html: null, highlights: [] }
  cachePreviewMemoId = undefined
}
