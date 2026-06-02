/** @typedef {{
 *   getCsrfToken?: () => string | null | undefined,
 *   wikiMemoLinkPath?: (memoId: string | number) => string,
 *   getScrollRoot?: () => HTMLElement | null,
 *   memoAssetSrc?: (memoId: string | number, relativePath: string) => string | null,
 *   memoAssetViewUrl?: (assetSrc: string | null) => string | null,
 *   diagramEditUrl?: (memoId: string | number, diagramKey: string) => string | null,
 *   diagramSourceUrl?: (memoId: string | number, diagramKey: string) => string | null,
 *   diagramViewUrl?: (memoId: string | number, diagramKey: string) => string | null,
 * }} HostConfigOverrides
 */

/** @type {HostConfigOverrides} */
let overrides = {}

/**
 * @param {HostConfigOverrides | null | undefined} config
 */
export function configureHost(config) {
  overrides = config ?? {}
}

export function resetHostConfig() {
  overrides = {}
}

export function getCsrfToken() {
  if (overrides.getCsrfToken) {
    const token = overrides.getCsrfToken()
    if (token) return token
  }

  const meta = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
  if (meta) return meta

  const formToken = document.querySelector('input[name="authenticity_token"]')?.value
  return formToken || null
}

/**
 * fetch 用 CSRF ヘッダー（meta が空でも form の authenticity_token を使う）。
 * @returns {Record<string, string>}
 */
export function csrfFetchHeaders() {
  const token = getCsrfToken()
  if (!token) return {}
  return { 'X-CSRF-Token': token }
}

/**
 * @param {string | number} memoId
 */
export function wikiMemoLinkPath(memoId) {
  if (overrides.wikiMemoLinkPath) return overrides.wikiMemoLinkPath(memoId)
  return `/memos/${memoId}`
}

export function getScrollRoot() {
  if (overrides.getScrollRoot) return overrides.getScrollRoot()
  return document.getElementById('memos_editor_scroll')
}

/**
 * @param {string | number} memoId
 * @param {string} relativePath
 */
export function memoAssetSrc(memoId, relativePath) {
  if (overrides.memoAssetSrc) return overrides.memoAssetSrc(memoId, relativePath)
  if (!memoId || !relativePath?.trim()) return null
  const path = relativePath
    .trim()
    .split('/')
    .map((seg) => encodeURIComponent(seg))
    .join('/')
  return `/memos/${encodeURIComponent(String(memoId))}/assets/${path}`
}

/**
 * @param {string | null} assetSrc
 */
export function memoAssetViewUrl(assetSrc) {
  if (overrides.memoAssetViewUrl) return overrides.memoAssetViewUrl(assetSrc)
  return assetSrc ? `${assetSrc}/view` : null
}

/**
 * @param {string | number} memoId
 * @param {string} diagramKey
 */
export function diagramEditUrl(memoId, diagramKey) {
  if (overrides.diagramEditUrl) return overrides.diagramEditUrl(memoId, diagramKey)
  if (!memoId || !diagramKey) return null
  return `/memos/${encodeURIComponent(String(memoId))}/diagrams/${encodeURIComponent(diagramKey)}/edit`
}

/**
 * @param {string | number} memoId
 * @param {string} diagramKey
 */
export function diagramSourceUrl(memoId, diagramKey) {
  if (overrides.diagramSourceUrl) return overrides.diagramSourceUrl(memoId, diagramKey)
  if (!memoId || !diagramKey) return null
  return `/memos/${encodeURIComponent(String(memoId))}/diagrams/${encodeURIComponent(diagramKey)}/source`
}

/**
 * @param {string | number} memoId
 * @param {string} diagramKey
 */
export function diagramViewUrl(memoId, diagramKey) {
  if (overrides.diagramViewUrl) return overrides.diagramViewUrl(memoId, diagramKey)
  if (!memoId || !diagramKey) return null
  return `/memos/${encodeURIComponent(String(memoId))}/diagrams/${encodeURIComponent(diagramKey)}/view`
}
