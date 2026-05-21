import { getAsciidoctor, getExtensionRegistry } from './instance.js'

const BLOCK_CONVERT_OPTIONS = {
  safe: 'secure',
  standalone: false,
  extension_registry: getExtensionRegistry(),
  attributes: {
    showtitle: true,
    experimental: '',
    'source-highlighter': 'highlight.js',
  },
}

/**
 * Convert a single AsciiDoc block fragment to HTML (preview body).
 *
 * @param {string} adoc
 * @returns {string}
 */
export function asciidocBlockToHtml(adoc) {
  const trimmed = adoc.trim()
  if (!trimmed) {
    return '<div class="paragraph"><p></p></div>'
  }

  return getAsciidoctor().convert(trimmed, BLOCK_CONVERT_OPTIONS)
}
