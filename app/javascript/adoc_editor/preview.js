import "highlight.js/styles/github.min.css"
import "./preview_hljs.css"

import { highlightPreviewCode } from "./asciidoc/codeHighlight.js"
import { resolvePreviewImages } from "./preview_assets.js"

/**
 * @param {string} html
 * @param {HTMLElement} container
 * @param {string | null | undefined} memoId
 */
export function renderPreviewHtml(html, container, memoId) {
  container.innerHTML = html
  resolvePreviewImages(container, memoId)
  highlightPreviewCode(container)
}
