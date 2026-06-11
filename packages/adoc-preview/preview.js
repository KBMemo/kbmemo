import { highlightPreviewCode } from '../adoc-codemirror/src/codeHighlight.js'
import { resolvePreviewImages } from "./preview_assets.js"
import { renderPreviewMath } from "./preview_math.js"
import { setTrustedHTML } from "./trusted_html.js"

/**
 * @param {string} html
 * @param {HTMLElement} container
 * @param {string | null | undefined} memoId
 */
export function renderPreviewHtml(html, container, memoId) {
  setTrustedHTML(container, "kbmemo-adoc-preview-html", html)
  resolvePreviewImages(container, memoId)
  highlightPreviewCode(container)
  renderPreviewMath(container)
}
