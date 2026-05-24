/** @typedef {{
 *   getCsrfToken?: () => string | null | undefined,
 *   wikiMemoLinkPath?: (memoId: string | number) => string,
 *   getScrollRoot?: () => HTMLElement | null,
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
  if (overrides.getCsrfToken) return overrides.getCsrfToken() ?? null
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ?? null
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
