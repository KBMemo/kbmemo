import Asciidoctor from '@asciidoctor/core'
import { createExtensionRegistry } from './extensions.js'

const asciidoctor = Asciidoctor()
const extensionRegistry = createExtensionRegistry(asciidoctor)

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

export function getAsciidoctor() {
  return asciidoctor
}

export function getExtensionRegistry() {
  return extensionRegistry
}

export function loadDocument(source) {
  return asciidoctor.load(source, PARSE_OPTIONS)
}
