import { configureHost } from './hostConfig.js'

/**
 * 汎用ホスト向け HostConfig（KBMemo 以外のプロジェクト用）。
 *
 * @param {{
 *   memoBase?: string,
 *   assetPath?: (memoId: string | number, relativePath: string) => string | null,
 *   wikiLinkPath?: (memoId: string | number) => string,
 *   diagramPath?: (memoId: string | number, diagramKey: string, action: 'edit' | 'source' | 'view') => string | null,
 *   getScrollRoot?: () => HTMLElement | null,
 * }} [options]
 */
export function configureVanillaHost({
  memoBase = '/memos',
  assetPath,
  wikiLinkPath,
  diagramPath,
  getScrollRoot,
} = {}) {
  configureHost({
    getScrollRoot,
    wikiMemoLinkPath: wikiLinkPath ?? ((memoId) => `${memoBase}/${memoId}`),
    memoAssetSrc(memoId, relativePath) {
      if (assetPath) return assetPath(memoId, relativePath)
      if (!memoId || !relativePath?.trim()) return null
      const path = relativePath
        .trim()
        .split('/')
        .map((seg) => encodeURIComponent(seg))
        .join('/')
      return `${memoBase}/${encodeURIComponent(String(memoId))}/assets/${path}`
    },
    diagramEditUrl(memoId, diagramKey) {
      if (diagramPath) return diagramPath(memoId, diagramKey, 'edit')
      if (!memoId || !diagramKey) return null
      return `${memoBase}/${encodeURIComponent(String(memoId))}/diagrams/${encodeURIComponent(diagramKey)}/edit`
    },
    diagramSourceUrl(memoId, diagramKey) {
      if (diagramPath) return diagramPath(memoId, diagramKey, 'source')
      if (!memoId || !diagramKey) return null
      return `${memoBase}/${encodeURIComponent(String(memoId))}/diagrams/${encodeURIComponent(diagramKey)}/source`
    },
    diagramViewUrl(memoId, diagramKey) {
      if (diagramPath) return diagramPath(memoId, diagramKey, 'view')
      if (!memoId || !diagramKey) return null
      return `${memoBase}/${encodeURIComponent(String(memoId))}/diagrams/${encodeURIComponent(diagramKey)}/view`
    },
  })
}
