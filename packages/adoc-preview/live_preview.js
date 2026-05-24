import { refreshPreview } from '@kbmemo/adoc-codemirror'
import { renderPreviewHtml } from './preview.js'

const PREVIEW_DEBOUNCE_MS = 300

/**
 * @param {object} options
 * @param {HTMLElement} options.previewEl
 * @param {HTMLSelectElement | null} [options.skinSelectEl]
 * @param {() => string | null | undefined} options.getMemoId
 * @param {() => string} options.getSource
 * @param {(selectEl: HTMLSelectElement, previewEl: HTMLElement) => void} [options.initPreviewSkinSelect]
 */
export function createLivePreview({ previewEl, skinSelectEl, getMemoId, getSource, initPreviewSkinSelect }) {
  if (skinSelectEl && initPreviewSkinSelect) {
    initPreviewSkinSelect(skinSelectEl, previewEl)
  }

  let timer

  function scheduleRender() {
    clearTimeout(timer)
    timer = setTimeout(() => {
      const source = getSource()
      const memoId = getMemoId()
      const { html } = refreshPreview(source, { memoId })
      renderPreviewHtml(html, previewEl, memoId)
    }, PREVIEW_DEBOUNCE_MS)
  }

  function renderNow() {
    clearTimeout(timer)
    const source = getSource()
    const memoId = getMemoId()
    const { html } = refreshPreview(source, { memoId })
    renderPreviewHtml(html, previewEl, memoId)
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
