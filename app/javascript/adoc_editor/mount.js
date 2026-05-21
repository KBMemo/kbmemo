/**
 * KBMemo 向け adoc_editor 統合の入口。
 * Phase A: AST ベースのシンタックスハイライト（asciidoc/codemirror.js）。
 * Phase B 以降: ライブプレビュー・WYSIWYG をここからマウントする。
 */
export { asciidocHighlight } from "./asciidoc/codemirror.js"
export { refreshHighlights, refreshPreview, clearParseCache } from "./asciidoc/parseSession.js"
export { createLivePreview } from "./live_preview.js"
