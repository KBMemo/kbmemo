export { asciidocHighlight } from './src/codemirror.js'
export { refreshHighlights, refreshPreview, clearParseCache } from './src/parseSession.js'
export { asciidocBlockToHtml } from './src/blockConvert.js'
export {
  adocForBlockConversion,
  indentLiteralFromPlainText,
  isIndentLiteralBlock,
  INDENT_LITERAL_DATA_ATTR,
  isBlankLine,
  indentForLiteralContinuation,
  splitIndentLiteralAtBlankLine,
  splitParagraphAtBlankLine,
  normalizeBlockSegmentText,
} from './src/literalParagraph.js'
export {
  formatHardBreakLine,
  isEmptyParagraphMarkerBr,
  lineHasHardBreakContinuation,
} from './src/hardbreakParagraph.js'
export { unitToAsciidoc } from './src/htmlToAsciidoc.js'
export { webHtmlToAsciidoc } from './src/webHtmlToAsciidoc.js'
export { highlightPreviewCode } from './src/codeHighlight.js'
export {
  getActiveUnitIndex,
  getCaretInFollowingBlock,
  getCaretOffsetInUnit,
  getSourceOffsetForLine,
  getTableParagraphSplit,
  hasBlankLineSeparator,
  parseEditUnitsFromSource,
  shouldSplitEditUnits,
} from './src/parseEditUnits.js'
