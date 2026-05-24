import "highlight.js/styles/github.min.css"
import "./preview_hljs.css"

import { highlightPreviewCode } from '@kbmemo/adoc-codemirror'
import { resolvePreviewImages } from "./preview_assets.js"
import { renderPreviewMath } from "./preview_math.js"

/**
 * @param {string} html
 * @param {HTMLElement} container
 * @param {string | null | undefined} memoId
 */
export function renderPreviewHtml(html, container, memoId) {
  container.innerHTML = html
  resolvePreviewImages(container, memoId)
  highlightPreviewCode(container)
  renderPreviewMath(container)
}
