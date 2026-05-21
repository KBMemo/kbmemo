import { refreshPreview } from "./asciidoc/parseSession.js"
import { renderPreviewHtml } from "./preview.js"
import { initPreviewSkinSelect } from "./preview_skin.js"

const ASCIIDOCTOR_CSS_ID = "kbmemo-adoc-preview-base"
const PREVIEW_DEBOUNCE_MS = 300

let baseStylesheetLoaded = false

function ensureBaseStylesheet() {
  if (baseStylesheetLoaded || document.getElementById(ASCIIDOCTOR_CSS_ID)) {
    baseStylesheetLoaded = true
    return
  }

  const link = document.createElement("link")
  link.id = ASCIIDOCTOR_CSS_ID
  link.rel = "stylesheet"
  link.href = "/css/asciidoctor.css"
  document.head.appendChild(link)
  baseStylesheetLoaded = true
}

/**
 * @param {object} options
 * @param {HTMLElement} options.previewEl
 * @param {HTMLSelectElement | null} [options.skinSelectEl]
 * @param {() => string | null | undefined} options.getMemoId
 * @param {() => string} options.getSource
 */
export function createLivePreview({ previewEl, skinSelectEl, getMemoId, getSource }) {
  ensureBaseStylesheet()

  if (skinSelectEl) {
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
    }
  }
}
