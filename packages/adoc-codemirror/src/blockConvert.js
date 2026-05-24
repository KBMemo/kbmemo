import { getAsciidoctor, getExtensionRegistry } from './instance.js'

const BLOCK_CONVERT_ATTRIBUTES = {
  showtitle: true,
  experimental: '',
  'source-highlighter': 'highlight.js',
  stem: 'latexmath',
}

/**
 * Convert a single AsciiDoc block fragment to HTML (preview body).
 *
 * @param {string} adoc
 * @param {string | null | undefined} [memoId]
 * @returns {string}
 */
export function asciidocBlockToHtml(adoc, memoId) {
  const trimmed = adoc.trim()
  if (!trimmed) {
    return '<div class="paragraph"><p></p></div>'
  }

  /** @type {Record<string, string>} */
  const attributes = { ...BLOCK_CONVERT_ATTRIBUTES }
  if (memoId != null && memoId !== '') {
    attributes.imagesdir = `/memos/${encodeURIComponent(String(memoId))}/assets/`
  }

  return getAsciidoctor().convert(trimmed, {
    safe: 'safe',
    standalone: false,
    extension_registry: getExtensionRegistry(),
    attributes,
  })
}
