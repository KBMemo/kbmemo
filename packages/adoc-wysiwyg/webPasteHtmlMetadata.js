/** @typedef {{ url?: string, title?: string }} WebPasteHtmlMetadata */

const KBMEMO_COMMENT_RE = /<!--\s*kbmemo:([\s\S]*?)\s*-->/i

/**
 * @param {string} html
 * @returns {WebPasteHtmlMetadata | null}
 */
export function extractKbmemoCommentMetadataFromHtml(html) {
  const match = html.match(KBMEMO_COMMENT_RE)
  if (!match) return null

  try {
    const parsed = JSON.parse(match[1])
    if (!parsed || typeof parsed !== 'object') return null

    return normalizeMetadata({
      url: parsed.url,
      title: parsed.title,
    })
  } catch {
    return null
  }
}

/**
 * @param {string} html
 * @returns {{ url: string, title?: string } | null}
 */
export function extractBlockquoteCiteFromHtml(html) {
  const trimmed = html.trim()
  if (!trimmed) return null

  const doc = new DOMParser().parseFromString(trimmed, 'text/html')
  const blockquote = doc.body.querySelector('blockquote[cite]')
  const cite = blockquote?.getAttribute('cite')?.trim()
  if (!cite) return null

  return { url: cite }
}

/**
 * Remove kbmemo metadata comments before HTML → AsciiDoc conversion.
 *
 * @param {string} html
 * @returns {string}
 */
export function stripKbmemoMetadataFromHtml(html) {
  return html.replace(KBMEMO_COMMENT_RE, '').trim()
}

/**
 * @param {{ url?: unknown, title?: unknown }} raw
 * @returns {WebPasteHtmlMetadata | null}
 */
function normalizeMetadata(raw) {
  const url = typeof raw.url === 'string' ? raw.url.trim() : undefined
  const title = typeof raw.title === 'string' ? raw.title.trim() : undefined
  if (!url && !title) return null
  return { url, title }
}

/**
 * @param {string} html
 * @returns {WebPasteHtmlMetadata}
 */
export function extractWebPasteMetadataFromHtml(html) {
  const fromComment = extractKbmemoCommentMetadataFromHtml(html)
  const fromBlockquote = extractBlockquoteCiteFromHtml(html)

  return {
    url: fromComment?.url || fromBlockquote?.url,
    title: fromComment?.title,
  }
}
