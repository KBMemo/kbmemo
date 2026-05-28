import { refreshPreview } from '@kbmemo/adoc-codemirror'
import { ensureWikiLinkLabelsInCache } from '@kbmemo/adoc-kbmemo'
import { renderPreviewHtml } from './preview.js'

const PREVIEW_DEBOUNCE_MS = 300

/**
 * @param {object} options
 * @param {HTMLElement} options.previewEl
 * @param {HTMLSelectElement | null} [options.skinSelectEl]
 * @param {() => string | null | undefined} options.getMemoId
 * @param {() => string} options.getSource
 * @param {() => { labelsUrl?: string, memoId?: string | null }} [options.getWikiConfig]
 * @param {(selectEl: HTMLSelectElement, previewEl: HTMLElement) => void} [options.initPreviewSkinSelect]
 */
export function createLivePreview({
  previewEl,
  skinSelectEl,
  getMemoId,
  getSource,
  getWikiConfig,
  initPreviewSkinSelect,
}) {
  if (skinSelectEl && initPreviewSkinSelect) {
    initPreviewSkinSelect(skinSelectEl, previewEl)
  }

  let timer
  let renderSeq = 0
  /** @type {Map<string, object>} */
  const wikiLabelCache = new Map()

  async function renderPreview() {
    const source = getSource()
    const memoId = getMemoId()
    const seq = ++renderSeq
    const wikiConfig = getWikiConfig?.()
    const labelsUrl = wikiConfig?.labelsUrl
    const wikiMemoId = wikiConfig?.memoId ?? memoId ?? null

    if (labelsUrl) {
      await ensureWikiLinkLabelsInCache(wikiLabelCache, labelsUrl, wikiMemoId, source)
      if (seq !== renderSeq) return
    }

    const { html } = refreshPreview(source, { memoId, wikiLabels: wikiLabelCache })
    renderPreviewHtml(html, previewEl, memoId)
  }

  function scheduleRender() {
    clearTimeout(timer)
    timer = setTimeout(() => {
      void renderPreview()
    }, PREVIEW_DEBOUNCE_MS)
  }

  function renderNow() {
    clearTimeout(timer)
    void renderPreview()
  }

  renderNow()

  return {
    scheduleRender,
    renderNow,
    destroy() {
      clearTimeout(timer)
    },
  }
}
