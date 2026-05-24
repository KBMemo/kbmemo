/**
 * Umbrella entry for AsciiDoc editor packages.
 * Phase 1: re-exports @kbmemo/adoc-codemirror; preview/WYSIWYG mount points stay in site adoc_editor/.
 */
export {
  asciidocHighlight,
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
