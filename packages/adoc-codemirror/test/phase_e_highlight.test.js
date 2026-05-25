// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { clearParseCache, refreshHighlights } from '../index.js'
import {
  extractSyntaxRefSections,
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

describe('Phase E syntax highlighting', () => {
  it('highlights include preprocessor lines', () => {
    const spans = spansForSection('includes')
    expect(hasClass(spans, 'adoc-include')).toBe(true)
  })

  it('highlights attribute definitions and references', () => {
    const spans = spansForSection('attributes')
    expect(hasClass(spans, 'adoc-attribute')).toBe(true)
    expect(hasClass(spans, 'adoc-attribute-ref')).toBe(true)
  })

  it('highlights counter attribute references in tables', () => {
    const spans = spansForSection('attributes-counter')
    expect(hasClass(spans, 'adoc-attribute-ref')).toBe(true)
  })

  it('highlights inline passthrough markup', () => {
    const spans = spansForSection('passthrough-inline')
    expect(hasClass(spans, 'adoc-passthrough')).toBe(true)
  })

  it('highlights passthrough block delimiters', () => {
    const spans = spansForSection('blocks-passthrough')
    expect(hasClass(spans, 'adoc-delimiter')).toBe(true)
  })

  it('highlights comment blocks and line comments', () => {
    const spans = spansForSection('comments')
    expect(hasClass(spans, 'adoc-comment')).toBe(true)
  })

  it('highlights thematic and page breaks', () => {
    expect(hasClass(spansForSection('breaks-thematic'), 'adoc-thematic-break')).toBe(true)
    expect(hasClass(spansForSection('breaks-page'), 'adoc-page-break')).toBe(true)
  })

  it('highlights delimited admonition labels and delimiters', () => {
    const spans = spansForSection('admonitions-block')
    expect(hasClass(spans, 'adoc-admonition-label')).toBe(true)
    expect(hasClass(spans, 'adoc-delimiter')).toBe(true)
  })

  it('highlights document header author and revision lines in the full fixture', () => {
    clearParseCache()
    const spans = refreshHighlights(SYNTAX_QUICK_REFERENCE)
    expect(hasClass(spans, 'adoc-document-header')).toBe(true)
  })
})
