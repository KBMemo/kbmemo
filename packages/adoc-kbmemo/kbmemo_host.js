import { configureHost, resetHostConfig } from './hostConfig.js'

/** KBMemo サイト向け HostConfig（スクロールルート等）を適用する。 */
export function configureKbmemoHost() {
  configureHost({
    getScrollRoot: () => document.getElementById('memos_editor_scroll'),
    wikiMemoLinkPath: (memoId) => `/memos/${memoId}`,
  })
}

export { resetHostConfig }
