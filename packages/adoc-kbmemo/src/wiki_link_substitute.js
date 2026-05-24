import { getCsrfToken, wikiMemoLinkPath } from '../hostConfig.js'

/** MemoWikiLinks と同じ [[target]] / [[target|label]] パターン */
export const WIKI_LINK_PATTERN = /\[\[([^\]|]+?)(?:\|([^\]]+?))?\]\]/g

const FENCE_LINE = /^```/

/**
 * @param {string} source
 * @returns {string[]}
 */
export function extractWikiLinkTargets(source) {
  /** @type {Set<string>} */
  const targets = new Set()
  let inFenced = false

  for (const line of source.split('\n')) {
    if (FENCE_LINE.test(line)) {
      inFenced = !inFenced
      continue
    }
    if (inFenced) continue

    for (const match of line.matchAll(WIKI_LINK_PATTERN)) {
      const target = match[1].trim()
      if (target) targets.add(target)
    }
  }

  return [...targets]
}

/**
 * @param {string} text
 */
function escapeAsciidocLinkText(text) {
  return text.replace(/]/g, '\\]')
}

/**
 * @param {string} text
 */
function escapeAsciidocUnquoted(text) {
  return text.replace(/#/g, '\\#')
}

/**
 * Asciidoctor プレビュー用に Wiki リンクを展開する（DB 上の [[...]] は変更しない）。
 *
 * @param {string} source
 * @param {Map<string, { display?: string, resolved?: boolean, slug?: boolean, memo_id?: number | null }>} labels
 */
export function substituteWikiLinksForPreview(source, labels) {
  if (!source) return source

  let inFenced = false
  return source
    .split('\n')
    .map((line) => {
      if (FENCE_LINE.test(line)) {
        inFenced = !inFenced
        return line
      }
      if (inFenced) return line

      return line.replace(WIKI_LINK_PATTERN, (match, rawTarget, rawCustom) => {
        const target = rawTarget.trim()
        const customLabel = rawCustom?.trim()
        const displayLabel = customLabel || target
        const entry = labels.get(target)

        if (entry?.resolved && entry.memo_id != null) {
          const linkLabel =
            customLabel || (entry.slug ? (entry.display ?? target) : target)
          return `link:${wikiMemoLinkPath(entry.memo_id)}[${escapeAsciidocLinkText(linkLabel)}]`
        }

        return `[.memo-wiki-broken]#${escapeAsciidocUnquoted(displayLabel)}#`
      })
    })
    .join('\n')
}

let fetchSeq = 0

/**
 * @param {string | undefined} url
 * @param {string | null | undefined} memoId
 * @param {string[]} targets
 * @returns {Promise<Map<string, object>>}
 */
export async function fetchWikiLinkLabelsMap(url, memoId, targets) {
  /** @type {Map<string, object>} */
  const labels = new Map()
  if (!url || targets.length === 0) return labels

  const endpoint = new URL(url, window.location.origin)
  if (memoId) endpoint.searchParams.set('memo_id', String(memoId))
  for (const target of targets) {
    endpoint.searchParams.append('targets[]', target)
  }

  const token = getCsrfToken()
  const seq = ++fetchSeq
  const res = await fetch(endpoint.toString(), {
    headers: {
      Accept: 'application/json',
      ...(token ? { 'X-CSRF-Token': token } : {}),
    },
    credentials: 'same-origin',
  })
  if (!res.ok || seq !== fetchSeq) return labels

  const data = await res.json()
  if (!data || typeof data !== 'object') return labels

  for (const [key, entry] of Object.entries(data)) {
    labels.set(key, entry)
  }
  return labels
}

/**
 * @param {Map<string, object>} cache
 * @param {string | undefined} url
 * @param {string | null | undefined} memoId
 * @param {string} source
 */
export async function ensureWikiLinkLabelsInCache(cache, url, memoId, source) {
  const missing = extractWikiLinkTargets(source).filter((target) => !cache.has(target))
  if (missing.length === 0) return

  const fetched = await fetchWikiLinkLabelsMap(url, memoId, missing)
  for (const [key, entry] of fetched) {
    cache.set(key, entry)
  }
}
