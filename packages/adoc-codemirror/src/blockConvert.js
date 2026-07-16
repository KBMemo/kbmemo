import { convert } from '@asciidoctor/core'
import { getExtensionRegistry } from './instance.js'
import { restrictPassthroughInSource } from '@kbmemo/adoc-kbmemo'
import { adocForBlockConversion } from './literalParagraph.js'

const BLOCK_CONVERT_ATTRIBUTES = {
  showtitle: true,
  experimental: '',
  icons: 'font',
  'source-highlighter': 'highlight.js',
  stem: 'latexmath',
}

/**
 * Convert a single AsciiDoc block fragment to HTML (preview body).
 *
 * @param {string} adoc
 * @param {string | null | undefined} [memoId]
 * @returns {Promise<string>}
 */
export async function asciidocBlockToHtml(adoc, memoId) {
  const trimmed = adoc.trim()
  if (!trimmed) {
    return '<div class="paragraph"><p></p></div>'
  }

  const toConvert = restrictPassthroughInSource(adocForBlockConversion(adoc))
  /** @type {Record<string, string>} */
  const attributes = { ...BLOCK_CONVERT_ATTRIBUTES }
  if (memoId != null && memoId !== '') {
    attributes.imagesdir = `/memos/${encodeURIComponent(String(memoId))}/assets/`
  }

  return convert(toConvert, {
    safe: 'safe',
    standalone: false,
    extension_registry: getExtensionRegistry(),
    attributes,
  })
}
