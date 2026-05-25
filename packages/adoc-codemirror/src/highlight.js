import { loadDocument } from './instance.js'
import { captureInlines, findInlineMarkup, inlineClassName } from './inlineCapture.js'
import { highlightCode } from './codeHighlight.js'

/** @typedef {{ from: number, to: number, className: string }} HighlightSpan */

const ADMONITION_LABELS = ['NOTE', 'TIP', 'IMPORTANT', 'WARNING', 'CAUTION']
const BLOCK_DELIMITER_LINES = new Set([
  '----', '....', '====', '____', '****', '--', '+++', '++++', '////',
])
const ADMONITION_ATTR_LINE = /^\[(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$/

const INLINE_CAPABLE = new Set([
  'paragraph',
  'table_cell',
  'list_item',
  'admonition',
])

/**
 * @param {string} source
 * @param {import('@asciidoctor/core').Document | null | undefined} doc
 * @returns {HighlightSpan[]}
 */
export function computeHighlights(source, doc = null) {
  const spans = []
  if (!source) return spans

  const lineStarts = buildLineStarts(source)
  const document = doc ?? loadDocument(source)
  const claimedLines = new Set()

  for (const block of document.findBy()) {
    const context = block.getContext()
    if (context === 'document') continue

    if (context === 'section') {
      highlightSection(block, source, lineStarts, spans, claimedLines)
      continue
    }

    if (context === 'paragraph' || context === 'table_cell') {
      highlightInlineBlock(block, document, source, lineStarts, spans, claimedLines)
      continue
    }

    if (context === 'listing') {
      highlightListing(block, source, lineStarts, spans, claimedLines)
      continue
    }

    if (context === 'literal') {
      highlightLiteralBlock(block, source, lineStarts, spans, claimedLines)
      continue
    }

    if (context === 'image') {
      highlightImageBlock(block, source, lineStarts, spans, claimedLines)
      continue
    }

    if (context === 'audio' || context === 'video') {
      highlightMediaBlock(block, source, lineStarts, spans, claimedLines, context)
      continue
    }

    if (context === 'admonition') {
      highlightAdmonition(block, document, source, lineStarts, spans, claimedLines)
      continue
    }

    if (context === 'table') {
      highlightTable(block, source, lineStarts, spans, claimedLines)
      continue
    }

    if (context === 'thematic_break' || context === 'page_break') {
      highlightBreakBlock(block, source, lineStarts, spans, claimedLines, context)
      continue
    }

    if (context === 'table_cell' || context === 'list_item' || context === 'ulist' || context === 'olist') {
      continue
    }

    if (INLINE_CAPABLE.has(context)) {
      highlightInlineBlock(block, document, source, lineStarts, spans, claimedLines)
      continue
    }

    highlightGenericBlock(block, document, source, lineStarts, spans, claimedLines)
  }

  highlightUnclaimedLines(document, source, lineStarts, spans, claimedLines)
  return mergeSpans(spans)
}

/**
 * @param {string} source
 * @returns {number[]}
 */
function buildLineStarts(source) {
  const starts = [0]
  for (let i = 0; i < source.length; i++) {
    if (source[i] === '\n') starts.push(i + 1)
  }
  return starts
}

/**
 * @param {number[]} lineStarts
 * @param {number} line 1-based
 */
function lineRange(lineStarts, line, sourceLength) {
  const from = lineStarts[line - 1] ?? 0
  const nextStart = lineStarts[line]
  const to = nextStart === undefined ? sourceLength : nextStart - 1
  return { from, to }
}

/**
 * @param {HighlightSpan[]} spans
 */
function addSpan(spans, from, to, className) {
  if (from >= to || from < 0) return
  spans.push({ from, to, className })
}

function claimLine(claimedLines, line) {
  claimedLines.add(line)
}

/**
 * @param {import('@asciidoctor/core').AbstractNode} node
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 */
function highlightInlinesWithAsciidoctor(node, text, baseOffset, spans) {
  if (!text || !node?.applySubstitutions) return

  const captured = captureInlines(node, text)
  let searchFrom = 0

  for (const inline of captured) {
    const range = findInlineMarkup(text, inline, searchFrom)
    if (!range) continue
    addSpan(spans, baseOffset + range.from, baseOffset + range.to, inlineClassName(inline))
    searchFrom = range.to
  }

  highlightImageMacrosInText(text, baseOffset, spans, searchFrom)
  highlightMediaMacrosInText(text, baseOffset, spans, searchFrom)
  highlightHardBreaksInText(text, baseOffset, spans)
  highlightSourceAnchorsInText(text, baseOffset, spans, searchFrom)
  highlightSupplementalInText(text, baseOffset, spans, searchFrom)
}

function highlightSection(block, source, lineStarts, spans, claimedLines) {
  const line = block.getLineNumber()
  if (!line) return

  const { from, to } = lineRange(lineStarts, line, source.length)
  const text = source.slice(from, to)
  const match = text.match(/^(=+)\s+(.*)$/)
  if (match) {
    addSpan(spans, from, from + match[1].length, `adoc-heading-marker adoc-h${block.getLevel()}`)
    addSpan(spans, from + match[0].length - match[2].length, to, `adoc-heading adoc-h${block.getLevel()}`)
  } else {
    addSpan(spans, from, to, `adoc-heading adoc-h${block.getLevel()}`)
  }
  claimLine(claimedLines, line)
}

function highlightInlineBlock(block, doc, source, lineStarts, spans, claimedLines) {
  if (block.getContext() === 'table_cell') {
    highlightTableCell(block, source, lineStarts, spans)
    return
  }

  const startLine = block.getLineNumber()
  const blockSource = block.getSource?.() ?? ''
  const lines = block.getSourceLines?.() || (blockSource ? [blockSource] : [])
  const role = block.getAttribute?.('role') ?? block.getRole?.()
  const isLead = role === 'lead'

  for (let i = 0; i < lines.length; i++) {
    const line = startLine + i
    const { from, to } = lineRange(lineStarts, line, source.length)
    const text = source.slice(from, to)

    if (/^include::/.test(text)) {
      addSpan(spans, from, to, 'adoc-include')
      claimLine(claimedLines, line)
      continue
    }

    if (isLead) {
      addSpan(spans, from, to, 'adoc-lead')
    }

    highlightLineContent(doc, text, from, spans)
    claimLine(claimedLines, line)
  }
}

function highlightTableCell(block, source, lineStarts, spans) {
  const line = block.getLineNumber()
  const cellSource = block.getSource?.() ?? ''
  if (!line || !cellSource) return

  const { from: lineFrom, to: lineTo } = lineRange(lineStarts, line, source.length)
  const lineText = source.slice(lineFrom, lineTo)
  const cellIndex = lineText.indexOf(cellSource)
  if (cellIndex < 0) return

  highlightInlinesWithAsciidoctor(block, cellSource, lineFrom + cellIndex, spans)
}

function highlightListing(block, source, lineStarts, spans, claimedLines) {
  const startLine = block.getLineNumber()
  const contentLines = block.getSourceLines() || []
  const style = block.getStyle?.() || block.getContext()
  const isSource = style === 'source'
  const language = block.getAttribute?.('language') ?? block.getAttribute?.('lang')

  const attrLine = startLine - 1
  if (attrLine >= 1) {
    const { from, to } = lineRange(lineStarts, attrLine, source.length)
    const text = source.slice(from, to)
    if (/^\[[^\]]+\]$/.test(text)) {
      addSpan(spans, from, to, 'adoc-block-attribute')
      claimLine(claimedLines, attrLine)
    }
  }

  const openLine = startLine
  const closeLine = startLine + contentLines.length + 1
  for (const line of [openLine, closeLine]) {
    const { from, to } = lineRange(lineStarts, line, source.length)
    addSpan(spans, from, to, 'adoc-delimiter')
    claimLine(claimedLines, line)
  }

  if (isSource && contentLines.length > 0) {
    const code = contentLines.join('\n')
    const contentStart = lineRange(lineStarts, startLine + 1, source.length).from
    const { spans: codeSpans } = highlightCode(code, language)
    for (const span of codeSpans) {
      addSpan(spans, contentStart + span.from, contentStart + span.to, span.className)
    }
    for (let i = 0; i < contentLines.length; i++) {
      const line = startLine + 1 + i
      const { from, to } = lineRange(lineStarts, line, source.length)
      highlightSourceCalloutsInText(source.slice(from, to), from, spans)
      claimLine(claimedLines, line)
    }
    return
  }

  for (let i = 0; i < contentLines.length; i++) {
    const line = startLine + 1 + i
    const { from, to } = lineRange(lineStarts, line, source.length)
    addSpan(spans, from, to, 'adoc-literal')
    claimLine(claimedLines, line)
  }
}

function highlightLiteralBlock(block, source, lineStarts, spans, claimedLines) {
  const startLine = block.getLineNumber()
  const contentLines = block.getSourceLines() || []

  for (let i = 0; i < contentLines.length; i++) {
    const line = startLine + i
    const { from, to } = lineRange(lineStarts, line, source.length)
    addSpan(spans, from, to, 'adoc-literal')
    claimLine(claimedLines, line)
  }
}

function highlightImageBlock(block, source, lineStarts, spans, claimedLines) {
  const line = block.getLineNumber()
  if (!line) return

  const { from, to } = lineRange(lineStarts, line, source.length)
  highlightImageMacrosInText(source.slice(from, to), from, spans, 0)
  claimLine(claimedLines, line)
}

/**
 * @param {import('@asciidoctor/core').Block} block
 * @param {string} source
 * @param {number[]} lineStarts
 * @param {HighlightSpan[]} spans
 * @param {Set<number>} claimedLines
 * @param {'audio' | 'video'} mediaType
 */
function highlightMediaBlock(block, source, lineStarts, spans, claimedLines, mediaType) {
  const line = block.getLineNumber()
  if (!line) return

  const { from, to } = lineRange(lineStarts, line, source.length)
  highlightMediaMacrosInText(source.slice(from, to), from, spans, 0, mediaType)
  claimLine(claimedLines, line)
}

/**
 * @param {import('@asciidoctor/core').Block} block
 * @param {string} source
 * @param {number[]} lineStarts
 * @param {HighlightSpan[]} spans
 * @param {Set<number>} claimedLines
 * @param {'thematic_break' | 'page_break'} breakType
 */
function highlightBreakBlock(block, source, lineStarts, spans, claimedLines, breakType) {
  const line = block.getLineNumber()
  if (!line) return

  const className = breakType === 'thematic_break' ? 'adoc-thematic-break' : 'adoc-page-break'
  const { from, to } = lineRange(lineStarts, line, source.length)
  addSpan(spans, from, to, className)
  claimLine(claimedLines, line)
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {number} fromIndex
 */
function highlightImageMacrosInText(text, baseOffset, spans, fromIndex = 0) {
  const pattern = /(?:image::|image:)([^\[\n]+)(\[[^\]]*\])?/g
  pattern.lastIndex = fromIndex

  let match
  while ((match = pattern.exec(text)) !== null) {
    const markerLength = match[0].startsWith('image::') ? 7 : 6
    addSpan(spans, baseOffset + match.index, baseOffset + match.index + markerLength, 'adoc-image-marker')
    addSpan(
      spans,
      baseOffset + match.index + markerLength,
      baseOffset + match.index + markerLength + match[1].length,
      'adoc-image-target',
    )
    if (match[2]) {
      addSpan(
        spans,
        baseOffset + match.index + markerLength + match[1].length,
        baseOffset + match.index + match[0].length,
        'adoc-image-alt',
      )
    }
  }
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {number} fromIndex
 * @param {'audio' | 'video' | null} [mediaType]
 */
function highlightMediaMacrosInText(text, baseOffset, spans, fromIndex = 0, mediaType = null) {
  const pattern = mediaType
    ? new RegExp(`${mediaType}::([^\\[\\n]+)(\\[[^\\]]*\\])?`, 'g')
    : /(?:audio|video)::([^\[\n]+)(\[[^\]]*\])?/g
  pattern.lastIndex = fromIndex

  let match
  while ((match = pattern.exec(text)) !== null) {
    const kind = mediaType ?? match[0].slice(0, match[0].indexOf('::'))
    const markerLength = kind.length + 2
    const markerClass = `adoc-${kind}-marker`
    const targetClass = `adoc-${kind}-target`
    const attrsClass = `adoc-${kind}-attrs`
    addSpan(spans, baseOffset + match.index, baseOffset + match.index + markerLength, markerClass)
    addSpan(
      spans,
      baseOffset + match.index + markerLength,
      baseOffset + match.index + markerLength + match[1].length,
      targetClass,
    )
    if (match[2]) {
      addSpan(
        spans,
        baseOffset + match.index + markerLength + match[1].length,
        baseOffset + match.index + match[0].length,
        attrsClass,
      )
    }
  }
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 */
function highlightHardBreaksInText(text, baseOffset, spans) {
  const match = text.match(/\s\+$/)
  if (!match) return
  addSpan(spans, baseOffset + text.length - 1, baseOffset + text.length, 'adoc-hardbreak')
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {number} fromIndex
 */
function highlightSourceAnchorsInText(text, baseOffset, spans, fromIndex = 0) {
  const patterns = [
    { regex: /\[\[[^\],]+\]\]/g, className: 'adoc-anchor' },
    { regex: /\[#[^,\]]+(?:,[^\]]+)?\]/g, className: 'adoc-anchor' },
    { regex: /anchor:[^\[]+\[\]/g, className: 'adoc-anchor' },
    { regex: /xref:[^\[]+\[[^\]]*\]/g, className: 'adoc-xref' },
    { regex: /<<[^>]+>>/g, className: 'adoc-xref' },
  ]

  for (const { regex, className } of patterns) {
    regex.lastIndex = fromIndex
    let match
    while ((match = regex.exec(text)) !== null) {
      addSpan(spans, baseOffset + match.index, baseOffset + match.index + match[0].length, className)
    }
  }
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {number} fromIndex
 */
function highlightSupplementalInText(text, baseOffset, spans, fromIndex = 0) {
  highlightEscapesInText(text, baseOffset, spans, fromIndex)
  highlightAutolinksInText(text, baseOffset, spans, fromIndex)
  highlightTextReplacementsInText(text, baseOffset, spans, fromIndex)
  highlightAttributeReferencesInText(text, baseOffset, spans, fromIndex)
  highlightPassthroughInText(text, baseOffset, spans, fromIndex)
  highlightSourceCalloutsInText(text, baseOffset, spans, fromIndex)
}

/**
 * @param {import('@asciidoctor/core').AbstractNode} node
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 */
function highlightLineContent(node, text, baseOffset, spans) {
  if (highlightChecklistInText(text, baseOffset, spans, node)) return
  if (highlightDlistInText(text, baseOffset, spans, node)) return
  highlightInlinesWithAsciidoctor(node, text, baseOffset, spans)
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {import('@asciidoctor/core').AbstractNode} node
 */
function highlightChecklistInText(text, baseOffset, spans, node) {
  const match = text.match(/^(\[[ xX*]\])(\s+)(.*)$/)
  if (!match) return false

  addSpan(spans, baseOffset, baseOffset + match[1].length, 'adoc-checklist-marker')
  const contentFrom = baseOffset + match[1].length + match[2].length
  highlightInlinesWithAsciidoctor(node, match[3], contentFrom, spans)
  return true
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {import('@asciidoctor/core').AbstractNode} node
 */
function highlightDlistInText(text, baseOffset, spans, node) {
  const match = text.match(/^(.+?)(::+)(\s*)(.*)$/)
  if (!match || match[2].length < 2) return false

  const termEnd = baseOffset + match[1].length
  const markerEnd = termEnd + match[2].length
  addSpan(spans, baseOffset, termEnd, 'adoc-dlist-term')
  addSpan(spans, termEnd, markerEnd, 'adoc-dlist-marker')

  if (match[4]) {
    highlightInlinesWithAsciidoctor(node, match[4], markerEnd + match[3].length, spans)
  }

  return true
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {number} fromIndex
 */
function highlightEscapesInText(text, baseOffset, spans, fromIndex = 0) {
  const pattern = /\\./g
  pattern.lastIndex = fromIndex
  let match
  while ((match = pattern.exec(text)) !== null) {
    addSpan(spans, baseOffset + match.index, baseOffset + match.index + match[0].length, 'adoc-escape')
  }
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {number} fromIndex
 */
function highlightAutolinksInText(text, baseOffset, spans, fromIndex = 0) {
  const patterns = [
    /(?<!\\)https?:\/\/[^\s\[\]<]+/g,
    /(?<!\\)[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g,
  ]

  for (const pattern of patterns) {
    pattern.lastIndex = fromIndex
    let match
    while ((match = pattern.exec(text)) !== null) {
      addSpan(spans, baseOffset + match.index, baseOffset + match.index + match[0].length, 'adoc-link')
    }
  }
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {number} fromIndex
 */
function highlightTextReplacementsInText(text, baseOffset, spans, fromIndex = 0) {
  const patterns = [
    /\(C\)/g,
    /\(R\)/g,
    /\(TM\)/g,
    /\.{3}/g,
    /(?<!\\)--(?!>)/g,
    /->/g,
    /=>/g,
    /<-/g,
    /<=(?!=)/g,
    />=/g,
  ]

  for (const pattern of patterns) {
    pattern.lastIndex = fromIndex
    let match
    while ((match = pattern.exec(text)) !== null) {
      addSpan(spans, baseOffset + match.index, baseOffset + match.index + match[0].length, 'adoc-replacement')
    }
  }
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {number} fromIndex
 */
function highlightSourceCalloutsInText(text, baseOffset, spans, fromIndex = 0) {
  const pattern = /<(\d+)>/g
  pattern.lastIndex = fromIndex
  let match
  while ((match = pattern.exec(text)) !== null) {
    addSpan(spans, baseOffset + match.index, baseOffset + match.index + match[0].length, 'adoc-callout')
  }
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {number} fromIndex
 */
function highlightAttributeReferencesInText(text, baseOffset, spans, fromIndex = 0) {
  const pattern = /\{[^{}\n]+\}/g
  pattern.lastIndex = fromIndex
  let match
  while ((match = pattern.exec(text)) !== null) {
    if (match.index > 0 && text[match.index - 1] === '\\') continue
    addSpan(spans, baseOffset + match.index, baseOffset + match.index + match[0].length, 'adoc-attribute-ref')
  }
}

/**
 * @param {string} text
 * @param {number} baseOffset
 * @param {HighlightSpan[]} spans
 * @param {number} fromIndex
 */
function highlightPassthroughInText(text, baseOffset, spans, fromIndex = 0) {
  const patterns = [
    /pass:\[[^\]]*\]/g,
    /\+\+\+[^+\n]*\+\+\+/g,
    /\+(?:\\.|[^+\n])+\+/g,
  ]

  for (const pattern of patterns) {
    pattern.lastIndex = fromIndex
    let match
    while ((match = pattern.exec(text)) !== null) {
      addSpan(spans, baseOffset + match.index, baseOffset + match.index + match[0].length, 'adoc-passthrough')
    }
  }
}

/**
 * @param {string[]} lines
 * @param {number} lineIndex 0-based
 */
function isDocumentHeaderLine(text, lines, lineIndex) {
  if (lineIndex < 1) return false
  if (!/^=\s+\S/.test(lines[0]?.trim() ?? '')) return false

  const trimmed = text.trim()
  if (!trimmed || /^:[\w-]+(?:[\w-]*):/.test(trimmed)) return false

  for (let index = 1; index < lineIndex; index++) {
    const previous = lines[index]?.trim() ?? ''
    if (!previous) return false
    if (/^:[\w-]+(?:[\w-]*):/.test(previous)) return false
  }

  if (/^v\d/.test(trimmed) || /^\d+(?:\.\d+)+,/.test(trimmed)) return true
  if (/<[^>\s]+@[^>\s]+>/.test(trimmed)) return true
  if (lineIndex === 1) return true

  return false
}

function highlightAdmonition(block, doc, source, lineStarts, spans, claimedLines) {
  const startLine = block.getLineNumber()
  const style = block.getStyle?.()
  const contentLines = block.getSourceLines() || []

  if (style && startLine > 1) {
    const labelLine = startLine - 1
    const { from, to } = lineRange(lineStarts, labelLine, source.length)
    const text = source.slice(from, to)
    if (/^\[(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$/.test(text)) {
      addSpan(spans, from, to, 'adoc-admonition-label')
      claimLine(claimedLines, labelLine)
    }
  }

  for (let i = 0; i < contentLines.length; i++) {
    const line = startLine + i
    const { from, to } = lineRange(lineStarts, line, source.length)
    const text = source.slice(from, to)

    const labelMatch = text.match(new RegExp(`^(${ADMONITION_LABELS.join('|')}):\\s*`))
    if (labelMatch) {
      addSpan(spans, from, from + labelMatch[0].length, 'adoc-admonition-label')
      highlightInlinesWithAsciidoctor(block, text.slice(labelMatch[0].length), from + labelMatch[0].length, spans)
    } else {
      highlightInlinesWithAsciidoctor(block, text, from, spans)
    }
    claimLine(claimedLines, line)
  }
}

function highlightTable(block, source, lineStarts, spans, claimedLines) {
  const startLine = block.getLineNumber()
  for (let offset = 0; offset < 8; offset++) {
    const line = startLine + offset
    if (line > lineStarts.length) break
    const { from, to } = lineRange(lineStarts, line, source.length)
    const text = source.slice(from, to)
    if (!text.trim()) break
    if (/^\|===+$/.test(text)) {
      addSpan(spans, from, to, 'adoc-delimiter')
    } else if (/^\|/.test(text)) {
      addSpan(spans, from, to, 'adoc-table')
      highlightSupplementalInText(text, from, spans, 0)
    } else {
      break
    }
    claimLine(claimedLines, line)
  }
}

function highlightGenericBlock(block, doc, source, lineStarts, spans, claimedLines) {
  const startLine = block.getLineNumber()
  const lines = block.getSourceLines?.() || block.getSource?.() ? [block.getSource()] : []
  if (lines.length === 0) return

  for (let i = 0; i < lines.length; i++) {
    const line = startLine + i
    const { from, to } = lineRange(lineStarts, line, source.length)
    addSpan(spans, from, to, `adoc-${block.getContext()}`)
    highlightInlinesWithAsciidoctor(block, source.slice(from, to), from, spans)
    claimLine(claimedLines, line)
  }
}

function highlightUnclaimedLines(doc, source, lineStarts, spans, claimedLines) {
  const lines = source.split('\n')
  for (let i = 0; i < lines.length; i++) {
    const line = i + 1
    if (claimedLines.has(line)) continue

    const text = lines[i]
    const { from, to } = lineRange(lineStarts, line, source.length)

    if (!text.trim()) continue

    if (text.trim() === '////') {
      i = highlightCommentBlock(lines, i, lineStarts, source.length, spans) - 1
      continue
    }

    if (/^\/\/(?::|[^:])/.test(text)) {
      addSpan(spans, from, to, 'adoc-comment')
      continue
    }

    if (/^include::/.test(text)) {
      addSpan(spans, from, to, 'adoc-include')
      continue
    }

    if (isDocumentHeaderLine(text, lines, i)) {
      addSpan(spans, from, to, 'adoc-document-header')
      continue
    }

    if (text.trim() === "'''") {
      addSpan(spans, from, to, 'adoc-thematic-break')
      continue
    }

    if (text.trim() === '<<<') {
      addSpan(spans, from, to, 'adoc-page-break')
      continue
    }

    if (BLOCK_DELIMITER_LINES.has(text.trim())) {
      addSpan(spans, from, to, 'adoc-delimiter')
      continue
    }

    if (/^:[\w-]+(?:[\w-]*):/.test(text)) {
      addSpan(spans, from, to, 'adoc-attribute')
      continue
    }

    if (ADMONITION_ATTR_LINE.test(text.trim())) {
      addSpan(spans, from, to, 'adoc-admonition-label')
      continue
    }

    if (text.trim() === '[qanda]') {
      addSpan(spans, from, to, 'adoc-qanda-label')
      continue
    }

    if (/^\.(\S.*)$/.test(text.trim()) && !text.trim().startsWith('..')) {
      addSpan(spans, from, to, 'adoc-block-title')
      continue
    }

    if (/^\[.*\]$/.test(text)) {
      addSpan(spans, from, to, 'adoc-block-attribute')
      continue
    }

    if (/^#{1,6}\s+\S/.test(text)) {
      const marker = text.match(/^#+/)[0]
      const level = Math.min(marker.length, 6) - 1
      const match = text.match(/^(#+)\s+(.*)$/)
      if (match) {
        addSpan(spans, from, from + match[1].length, `adoc-heading-marker adoc-h${level}`)
        addSpan(spans, from + match[0].length - match[2].length, to, `adoc-heading adoc-h${level}`)
      }
      continue
    }

    if (/^={1,6}\s+\S/.test(text)) {
      const level = text.match(/^=+/)[0].length - 1
      const match = text.match(/^(=+)\s+(.*)$/)
      if (match) {
        addSpan(spans, from, from + match[1].length, `adoc-heading-marker adoc-h${level}`)
        addSpan(spans, from + match[0].length - match[2].length, to, `adoc-heading adoc-h${level}`)
      }
      continue
    }

    const listMatch = text.match(/^(\s*(?:\d+\.|[a-zA-Z]\.|[ixvmIXVM]+\)|[*\-+.]+)\s+)(.*)$/)
    if (listMatch) {
      addSpan(spans, from, from + listMatch[1].length, 'adoc-list-marker')
      highlightLineContent(doc, listMatch[2], from + listMatch[1].length, spans)
      continue
    }

    if (highlightDlistInText(text, from, spans, doc)) {
      continue
    }

    highlightLineContent(doc, text, from, spans)
  }
}

/**
 * @param {string[]} lines
 * @param {number} openIndex 0-based opening `////` line
 * @param {number[]} lineStarts
 * @param {number} sourceLength
 * @param {HighlightSpan[]} spans
 * @returns {number} next line index to continue from (0-based, exclusive)
 */
function highlightCommentBlock(lines, openIndex, lineStarts, sourceLength, spans) {
  let closeIndex = openIndex + 1
  while (closeIndex < lines.length && lines[closeIndex].trim() !== '////') {
    closeIndex++
  }

  const endIndex = closeIndex < lines.length ? closeIndex : openIndex
  for (let index = openIndex; index <= endIndex; index++) {
    const line = index + 1
    const { from, to } = lineRange(lineStarts, line, sourceLength)
    addSpan(spans, from, to, 'adoc-comment')
  }

  return endIndex + 1
}

function mergeSpans(spans) {
  return spans.sort((a, b) => a.from - b.from || a.to - b.to)
}
