import "./wysiwyg.css"
import "./contextMenu.css"

import { createWysiwygEditor } from "./wysiwyg.js"
import { applyPreviewSkin, getStoredSkinId } from "./preview_skin.js"

const LEGACY_ASCIIDOCTOR_LINK_ID = "kbmemo-adoc-preview-base"

/** 旧実装が head に載せたグローバル asciidoctor.css を除去する */
function removeLegacyGlobalStylesheet() {
  document.getElementById(LEGACY_ASCIIDOCTOR_LINK_ID)?.remove()
}

/**
 * @param {object} options
 * @param {HTMLElement} options.editorEl
 * @param {HTMLElement} options.toolbarEl
 * @param {HTMLElement} [options.paneEl]
 * @param {() => string | null | undefined} [options.getMemoId]
 * @param {() => { completionsUrl?: string, labelsUrl?: string, memoId?: string | null }} [options.getWikiConfig]
 * @param {(source: string) => void} options.onSourceChange
 */
export function createMemoWysiwygEditor({ editorEl, toolbarEl, paneEl, getMemoId, getWikiConfig, onSourceChange }) {
  removeLegacyGlobalStylesheet()
  applyPreviewSkin(editorEl, getStoredSkinId())

  return createWysiwygEditor(editorEl, toolbarEl, {
    paneEl,
    getMemoId,
    getWikiConfig,
    onSourceChange,
  })
}
