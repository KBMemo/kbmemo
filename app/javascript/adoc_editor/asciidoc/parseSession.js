import { loadDocument } from './instance.js'
import { computeHighlights } from './highlight.js'

/** @typedef {{ from: number, to: number, className: string }} HighlightSpan */
/** @typedef {{ source: string, doc: import('@asciidoctor/core').Document, html: string | null, highlights: HighlightSpan[] }} ParseCache */

/** @type {ParseCache} */
let cache = { source: '', doc: null, html: null, highlights: [] }

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
  return highlights
}

/**
 * Parse for preview HTML (debounced).
 * Reuses doc/highlights from {@link refreshHighlights} when possible.
 *
 * @param {string} source
 */
export function refreshPreview(source) {
  if (cache.source === source && cache.html) {
    return { html: cache.html, highlights: cache.highlights }
  }

  if (cache.source !== source || !cache.doc) {
    const doc = loadDocument(source)
    const highlights = computeHighlights(source, doc)
    cache = { source, doc, highlights, html: null }
  }

  cache.html = cache.doc.convert()
  return { html: cache.html, highlights: cache.highlights }
}

export function clearParseCache() {
  cache = { source: '', doc: null, html: null, highlights: [] }
}
