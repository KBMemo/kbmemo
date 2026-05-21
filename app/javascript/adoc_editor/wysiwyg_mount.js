import "./wysiwyg.css"
import "./contextMenu.css"

import { createWysiwygEditor } from "./wysiwyg.js"
import { applyPreviewSkin, getStoredSkinId } from "./preview_skin.js"

const ASCIIDOCTOR_CSS_ID = "kbmemo-adoc-preview-base"

function ensureBaseStylesheet() {
  if (document.getElementById(ASCIIDOCTOR_CSS_ID)) return

  const link = document.createElement("link")
  link.id = ASCIIDOCTOR_CSS_ID
  link.rel = "stylesheet"
  link.href = "/css/asciidoctor.css"
  document.head.appendChild(link)
}

/**
 * @param {object} options
 * @param {HTMLElement} options.editorEl
 * @param {HTMLElement} options.toolbarEl
 * @param {HTMLElement} [options.paneEl]
 * @param {() => string | null | undefined} [options.getMemoId]
 * @param {(source: string) => void} options.onSourceChange
 */
export function createMemoWysiwygEditor({ editorEl, toolbarEl, paneEl, getMemoId, onSourceChange }) {
  ensureBaseStylesheet()
  applyPreviewSkin(editorEl, getStoredSkinId())

  return createWysiwygEditor(editorEl, toolbarEl, {
    paneEl,
    getMemoId,
    onSourceChange
  })
}
