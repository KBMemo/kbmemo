import '@kbmemo/adoc-wysiwyg/wysiwyg.css'
import '@kbmemo/adoc-wysiwyg/contextMenu.css'

import { Decoration, EditorView, keymap, MatchDecorator, ViewPlugin } from '@codemirror/view'
import { createWysiwygEditor } from '@kbmemo/adoc-wysiwyg'
import { createKbmemoWysiwygSourceExtensions } from '@kbmemo/adoc-kbmemo'
import { getCspNonce } from '../security/csp_nonce'

const LEGACY_ASCIIDOCTOR_LINK_ID = 'kbmemo-adoc-preview-base'
const codeMirrorView = { Decoration, EditorView, keymap, MatchDecorator, ViewPlugin }

/** 旧実装が head に載せたグローバル asciidoctor.css を除去する */
function removeLegacyGlobalStylesheet() {
  document.getElementById(LEGACY_ASCIIDOCTOR_LINK_ID)?.remove()
}

/**
 * @param {object} options
 * @param {HTMLElement} options.editorEl
 * @param {HTMLElement} [options.paneEl]
 * @param {() => string | null | undefined} [options.getMemoId]
 * @param {() => { completionsUrl?: string, labelsUrl?: string, memoId?: string | null }} [options.getWikiConfig]
 * @param {(source: string) => void} options.onSourceChange
 * @param {(event: ClipboardEvent) => boolean | void} [options.onImagePaste]
 */
export function createMemoWysiwygEditor({ editorEl, paneEl, getMemoId, getWikiConfig, onSourceChange, onImagePaste }) {
  removeLegacyGlobalStylesheet()

  return createWysiwygEditor(editorEl, {
    paneEl,
    getMemoId,
    getWikiConfig,
    codeMirrorView,
    cspNonce: getCspNonce(),
    sourceExtensions: createKbmemoWysiwygSourceExtensions({
      getWikiConfig,
      getMemoId,
      codeMirrorView,
    }),
    onSourceChange,
    onImagePaste,
  })
}
