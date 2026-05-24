/**
 * KBMemo 向け adoc_editor 統合の入口。
 * Phase A: AST ベースのシンタックスハイライト（@kbmemo/adoc-codemirror）。
 * Phase B 以降: ライブプレビュー・WYSIWYG をここからマウントする。
 */
export {
  asciidocHighlight,
  refreshHighlights,
  refreshPreview,
  clearParseCache,
} from '@kbmemo/adoc-codemirror'
export { createLivePreview } from "./live_preview.js"
export { createMemoWysiwygEditor } from "./wysiwyg_mount.js"
