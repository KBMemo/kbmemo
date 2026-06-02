import { getCsrfToken } from '../hostConfig.js'

const FENCE_LINE = /^```/
const ULID = '[0-9A-HJKMNP-TV-Z]{26}'
const ALBUM_LINE = new RegExp(`^album::(${ULID})(\\[[^\\]]*\\])?\\s*$`, 'i')
const MEDIA_IMAGE = new RegExp(`image::media:(${ULID})(\\[[^\\]]*\\])?`, 'gi')

/**
 * @param {string} text
 */
function escapeAsciidocUnquoted(text) {
  return text.replace(/#/g, '\\#')
}

/**
 * @param {string} source
 * @returns {string[]}
 */
export function extractTsuzuraMediaIds(source) {
  /** @type {Set<string>} */
  const ids = new Set()
  let inFenced = false

  for (const line of source.split('\n')) {
    if (FENCE_LINE.test(line)) {
      inFenced = !inFenced
      continue
    }
    if (inFenced) continue

    for (const match of line.matchAll(MEDIA_IMAGE)) {
      ids.add(match[1].toUpperCase())
    }
  }

  return [...ids]
}

/**
 * @param {string} source
 * @returns {string[]}
 */
export function extractTsuzuraAlbumIds(source) {
  /** @type {Set<string>} */
  const ids = new Set()
  let inFenced = false

  for (const line of source.split('\n')) {
    if (FENCE_LINE.test(line)) {
      inFenced = !inFenced
      continue
    }
    if (inFenced) continue

    const match = line.match(ALBUM_LINE)
    if (match) ids.add(match[1].toUpperCase())
  }

  return [...ids]
}

/**
 * @param {string} ulid
 * @param {string} attrs
 * @param {Map<string, string>} urls
 */
function replaceMediaMacro(ulid, attrs, urls) {
  const id = ulid.toUpperCase()
  const url = urls.get(id)
  if (!url) return `[.tsuzura-missing]#media:${id}#`
  return `image::${url}${attrs || '[]'}`
}

/**
 * @param {string} albumId
 * @param {{ urls: Map<string, string>, albums: Map<string, string[]> }} cache
 */
function replaceAlbumLine(albumId, cache) {
  const id = albumId.toUpperCase()
  const mediaIds = cache.albums.get(id) ?? []
  if (mediaIds.length === 0) return `[.tsuzura-missing]#album:${id}#`
  return mediaIds.map((mediaId) => replaceMediaMacro(mediaId, '[]', cache.urls)).join('\n')
}

/**
 * MemoTsuzuraMacro と同様に album:: / image::media: を署名 URL へ展開（DB ソースは変更しない）。
 *
 * @param {string} source
 * @param {{ urls?: Map<string, string>, albums?: Map<string, string[]> }} [cache]
 */
export function substituteTsuzuraForPreview(source, cache = {}) {
  if (!source) return source

  const urls = cache.urls ?? new Map()
  const albums = cache.albums ?? new Map()
  const tsuzuraCache = { urls, albums }

  let inFenced = false
  return source
    .split('\n')
    .map((line) => {
      if (FENCE_LINE.test(line)) {
        inFenced = !inFenced
        return line
      }
      if (inFenced) return line

      const albumMatch = line.match(ALBUM_LINE)
      if (albumMatch) {
        return replaceAlbumLine(albumMatch[1], tsuzuraCache)
      }

      return line.replace(MEDIA_IMAGE, (_, ulid, attrs) =>
        replaceMediaMacro(ulid, attrs ?? '[]', urls),
      )
    })
    .join('\n')
}

let fetchSeq = 0

/**
 * @param {string | undefined} authorizeUrl
 * @param {string | null | undefined} memoId
 * @param {string[]} mediaIds
 * @param {string[]} albumIds
 * @returns {Promise<{ urls: Map<string, string>, albums: Map<string, string[]> }>}
 */
export async function fetchTsuzuraPreviewCache(authorizeUrl, memoId, mediaIds, albumIds) {
  /** @type {Map<string, string>} */
  const urls = new Map()
  /** @type {Map<string, string[]>} */
  const albums = new Map()

  if (!authorizeUrl || !memoId || (mediaIds.length === 0 && albumIds.length === 0)) {
    return { urls, albums }
  }

  const endpoint = new URL(authorizeUrl, window.location.origin)
  const token = getCsrfToken()
  const body = new FormData()
  body.set('memo_id', String(memoId))
  for (const id of mediaIds) body.append('media_ids[]', id)
  for (const id of albumIds) body.append('album_ids[]', id)

  const seq = ++fetchSeq
  const res = await fetch(endpoint.toString(), {
    method: 'POST',
    body,
    headers: {
      Accept: 'application/json',
      ...(token ? { 'X-CSRF-Token': token } : {}),
    },
    credentials: 'same-origin',
  })
  if (!res.ok || seq !== fetchSeq) return { urls, albums }

  const data = await res.json()
  if (!data || typeof data !== 'object') return { urls, albums }

  for (const [key, value] of Object.entries(data.urls ?? {})) {
    if (typeof value === 'string' && value) urls.set(key.toUpperCase(), value)
  }
  for (const [key, value] of Object.entries(data.albums ?? {})) {
    if (Array.isArray(value)) {
      albums.set(
        key.toUpperCase(),
        value.map((entry) => String(entry).toUpperCase()),
      )
    }
  }

  return { urls, albums }
}

/**
 * @param {{ urls: Map<string, string>, albums: Map<string, string[]> }} cache
 * @param {string | undefined} authorizeUrl
 * @param {string | null | undefined} memoId
 * @param {string} source
 */
export async function ensureTsuzuraUrlsInCache(cache, authorizeUrl, memoId, source) {
  if (!authorizeUrl || !memoId) return

  const mediaIds = extractTsuzuraMediaIds(source).filter((id) => !cache.urls.has(id))
  const albumIds = extractTsuzuraAlbumIds(source).filter((id) => !cache.albums.has(id))
  if (mediaIds.length === 0 && albumIds.length === 0) return

  const fetched = await fetchTsuzuraPreviewCache(authorizeUrl, memoId, mediaIds, albumIds)
  for (const [key, value] of fetched.urls) {
    if (!cache.urls.has(key)) cache.urls.set(key, value)
  }
  for (const [key, value] of fetched.albums) {
    if (!cache.albums.has(key)) cache.albums.set(key, value)
  }
}

/**
 * @param {{ urls: Map<string, string>, albums: Map<string, string[]> } | undefined} cache
 */
export function tsuzuraCacheKey(cache) {
  if (!cache) return ''
  const urlPart = [...cache.urls.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}\t${value}`)
    .join('\n')
  const albumPart = [...cache.albums.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, ids]) => `${key}\t${ids.join(',')}`)
    .join('\n')
  return `${urlPart}\n---\n${albumPart}`
}
