/**
 * Umbrella entry for AsciiDoc editor packages.
 *
 * CSS (bundler 側で import):
 * - @kbmemo/adoc-wysiwyg/wysiwyg.css
 * - @kbmemo/adoc-wysiwyg/contextMenu.css
 * - @kbmemo/adoc-preview/preview_hljs.css
 * - highlight.js/styles/github.min.css
 * - katex/dist/katex.min.css (preview / math WYSIWYG 使用時)
 */
export {
  createAsciidocHighlight,
  refreshHighlights,
  refreshPreview,
  clearParseCache,
  asciidocBlockToHtml,
  unitToAsciidoc,
  webHtmlToAsciidoc,
  highlightPreviewCode,
  getActiveUnitIndex,
  getCaretInFollowingBlock,
  getCaretOffsetInUnit,
  getSourceOffsetForLine,
  getTableParagraphSplit,
  hasBlankLineSeparator,
  parseEditUnitsFromSource,
  shouldSplitEditUnits,
} from '@kbmemo/adoc-codemirror'

export { createLivePreview, renderPreviewHtml } from '@kbmemo/adoc-preview'

export { createWysiwygEditor, createWysiwygSourceExtensions } from '@kbmemo/adoc-wysiwyg'

export {
  configureHost,
  configureKbmemoHost,
  configureVanillaHost,
  createKbmemoWysiwygSourceExtensions,
  resetHostConfig,
} from '@kbmemo/adoc-kbmemo'
