import { load } from '@asciidoctor/core'
import { createExtensionRegistry } from './extensions.js'

const extensionRegistry = createExtensionRegistry()

const PARSE_OPTIONS = {
  safe: 'secure',
  sourcemap: true,
  extension_registry: extensionRegistry,
  attributes: {
    showtitle: true,
    experimental: '',
    icons: 'font',
    'source-highlighter': 'highlight.js',
    stem: 'latexmath',
  },
}

export function getExtensionRegistry() {
  return extensionRegistry
}

/**
 * @param {string} source
 * @returns {Promise<import('@asciidoctor/core').Document>}
 */
export async function loadDocument(source) {
  return load(source, PARSE_OPTIONS)
}
