import { extractWebPasteMetadataFromHtml } from './webPasteHtmlMetadata.js'

export const KBMEMO_CLIP_MIME = 'application/x-kbmemo-clip+json'

/**
 * @typedef {{ url?: string, title?: string }} WebPasteMetadata
 */

/**
 * @param {DataTransfer | null | undefined} clipboardData
 * @param {string} [html]
 * @returns {WebPasteMetadata}
 */
export function extractWebPasteMetadata(clipboardData, html = '') {
  const fromCustomMime = readKbmemoClipMetadata(clipboardData) ?? {}
  const fromHtml = html ? extractWebPasteMetadataFromHtml(html) : {}
  const fromUriList = readUriListMetadata(clipboardData) ?? {}

  return {
    url: fromCustomMime.url || fromHtml.url || fromUriList.url,
    title: fromCustomMime.title || fromHtml.title || fromUriList.title,
  }
}

/**
 * @param {DataTransfer | null | undefined} clipboardData
 * @returns {WebPasteMetadata | null}
 */
function readKbmemoClipMetadata(clipboardData) {
  if (!clipboardData?.types?.includes(KBMEMO_CLIP_MIME)) return null

  const raw = clipboardData.getData(KBMEMO_CLIP_MIME)
  if (!raw?.trim()) return null
  return parseKbmemoClipJson(raw)
}

/**
 * @param {DataTransfer | null | undefined} clipboardData
 * @returns {WebPasteMetadata | null}
 */
function readUriListMetadata(clipboardData) {
  if (!clipboardData?.types?.includes('text/uri-list')) return null

  const raw = clipboardData.getData('text/uri-list') ?? ''
  const url = raw
    .split('\n')
    .map((line) => line.trim())
    .find((line) => line && !line.startsWith('#'))

  if (!url) return null
  return { url }
}

/**
 * @param {string} raw
 * @returns {WebPasteMetadata | null}
 */
export function parseKbmemoClipJson(raw) {
  try {
    const parsed = JSON.parse(raw)
    if (!parsed || typeof parsed !== 'object') return null

    return {
      url: typeof parsed.url === 'string' ? parsed.url.trim() : undefined,
      title: typeof parsed.title === 'string' ? parsed.title.trim() : undefined,
    }
  } catch {
    return null
  }
}
