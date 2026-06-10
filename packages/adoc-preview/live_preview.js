import { refreshPreview } from '../adoc-codemirror/src/parseSession.js'
import { ensureDiagramSvgsInCache } from '../adoc-kbmemo/src/diagram_substitute.js'
import { ensureTsuzuraUrlsInCache } from '../adoc-kbmemo/src/tsuzura_substitute.js'
import { ensureWikiLinkLabelsInCache } from '../adoc-kbmemo/src/wiki_link_substitute.js'
import { renderPreviewHtml } from './preview.js'

const PREVIEW_DEBOUNCE_MS = 300

/**
 * @param {object} options
 * @param {HTMLElement} options.previewEl
 * @param {HTMLSelectElement | null} [options.skinSelectEl]
 * @param {() => string | null | undefined} options.getMemoId
 * @param {() => string} options.getSource
 * @param {() => { labelsUrl?: string, memoId?: string | null, tsuzuraAuthorizeUrl?: string | null }} [options.getWikiConfig]
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
  /** @type {{ urls: Map<string, string>, albums: Map<string, string[]> }} */
  const tsuzuraCache = { urls: new Map(), albums: new Map() }
  /** @type {Map<string, boolean>} */
  const diagramAvailabilityCache = new Map()

  async function renderPreview() {
    const source = getSource()
    const memoId = getMemoId()
    const seq = ++renderSeq
    const wikiConfig = getWikiConfig?.()
    const labelsUrl = wikiConfig?.labelsUrl
    const wikiMemoId = wikiConfig?.memoId ?? memoId ?? null
    const tsuzuraAuthorizeUrl = wikiConfig?.tsuzuraAuthorizeUrl

    if (labelsUrl) {
      await ensureWikiLinkLabelsInCache(wikiLabelCache, labelsUrl, wikiMemoId, source)
      if (seq !== renderSeq) return
    }

    if (tsuzuraAuthorizeUrl && memoId) {
      await ensureTsuzuraUrlsInCache(tsuzuraCache, tsuzuraAuthorizeUrl, memoId, source)
      if (seq !== renderSeq) return
    }

    if (memoId) {
      await ensureDiagramSvgsInCache(diagramAvailabilityCache, memoId, source)
      if (seq !== renderSeq) return
    }

    const { html } = refreshPreview(source, {
      memoId,
      diagramAvailability: memoId ? diagramAvailabilityCache : undefined,
      wikiLabels: wikiLabelCache,
      tsuzuraCache,
    })
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
