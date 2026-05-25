// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { clearParseCache, refreshHighlights } from '../index.js'
import {
  extractSyntaxRefSections,
  wrapSyntaxRefSection,
  SYNTAX_QUICK_REFERENCE,
} from '@kbmemo/test-fixtures'

/** @param {string} id */
function spansForSection(id) {
  clearParseCache()
  const section = extractSyntaxRefSections(SYNTAX_QUICK_REFERENCE).find((entry) => entry.id === id)
  if (!section) throw new Error(`missing syntax-ref section: ${id}`)
  return refreshHighlights(section.adoc)
}

/** @param {ReturnType<typeof refreshHighlights>} spans @param {string} className */
function hasClass(spans, className) {
  return spans.some((span) => span.className.includes(className))
}

describe('Phase C syntax highlighting', () => {
  it('highlights unconstrained emphasis and monospace', () => {
    const spans = spansForSection('text-formatting-unconstrained')
    expect(hasClass(spans, 'adoc-emphasis')).toBe(true)
    expect(hasClass(spans, 'adoc-strong')).toBe(true)
    expect(hasClass(spans, 'adoc-monospace')).toBe(true)
  })

  it('highlights marked and role-based text', () => {
    const spans = spansForSection('text-formatting-highlight')
    expect(hasClass(spans, 'adoc-highlight')).toBe(true)
  })

  it('highlights superscript and subscript', () => {
    const spans = spansForSection('text-formatting-super-sub')
    expect(hasClass(spans, 'adoc-superscript')).toBe(true)
    expect(hasClass(spans, 'adoc-subscript')).toBe(true)
  })

  it('highlights anchors and cross references', () => {
    const spans = spansForSection('links-anchors')
    expect(hasClass(spans, 'adoc-anchor')).toBe(true)

    const xrefSpans = spansForSection('links-xref')
    expect(hasClass(xrefSpans, 'adoc-xref')).toBe(true)

    const interdocSpans = spansForSection('links-interdoc')
    expect(hasClass(interdocSpans, 'adoc-xref')).toBe(true)
  })

  it('highlights literal paragraphs without delimiter noise', () => {
    const spans = spansForSection('paragraphs-literal')
    expect(hasClass(spans, 'adoc-literal')).toBe(true)
    expect(spans.some((span) => span.className === 'adoc-delimiter')).toBe(false)
  })

  it('highlights hard line breaks', () => {
    clearParseCache()
    const spans = refreshHighlights(wrapSyntaxRefSection('Roses are red, +\nviolets are blue.'))
    expect(hasClass(spans, 'adoc-hardbreak')).toBe(true)
  })
})
