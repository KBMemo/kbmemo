// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { clearParseCache, refreshHighlights } from '../index.js'
import {
  extractSyntaxRefSections,
  SYNTAX_QUICK_REFERENCE,
} from '@kbmemo/test-fixtures'

/** @param {string} id */
async function spansForSection(id) {
  clearParseCache()
  const section = extractSyntaxRefSections(SYNTAX_QUICK_REFERENCE).find((entry) => entry.id === id)
  if (!section) throw new Error(`missing syntax-ref section: ${id}`)
  return await refreshHighlights(section.adoc)
}

/** @param {Awaited<ReturnType<typeof refreshHighlights>>} spans @param {string} className */
function hasClass(spans, className) {
  return spans.some((span) => span.className.includes(className))
}

describe('Phase E syntax highlighting', () => {
  it('highlights include preprocessor lines', async () => {
    const spans = await spansForSection('includes')
    expect(hasClass(spans, 'adoc-include')).toBe(true)
  })

  it('highlights attribute definitions and references', async () => {
    const spans = await spansForSection('attributes')
    expect(hasClass(spans, 'adoc-attribute')).toBe(true)
    expect(hasClass(spans, 'adoc-attribute-ref')).toBe(true)
  })

  it('highlights counter attribute references in tables', async () => {
    const spans = await spansForSection('attributes-counter')
    expect(hasClass(spans, 'adoc-attribute-ref')).toBe(true)
  })

  it('highlights inline passthrough markup', async () => {
    const spans = await spansForSection('passthrough-inline')
    expect(hasClass(spans, 'adoc-passthrough')).toBe(true)
  })

  it('highlights passthrough block delimiters', async () => {
    const spans = await spansForSection('blocks-passthrough')
    expect(hasClass(spans, 'adoc-delimiter')).toBe(true)
  })

  it('highlights comment blocks and line comments', async () => {
    const spans = await spansForSection('comments')
    expect(hasClass(spans, 'adoc-comment')).toBe(true)
  })

  it('highlights thematic and page breaks', async () => {
    expect(hasClass(await spansForSection('breaks-thematic'), 'adoc-thematic-break')).toBe(true)
    expect(hasClass(await spansForSection('breaks-page'), 'adoc-page-break')).toBe(true)
  })

  it('highlights delimited admonition labels and delimiters', async () => {
    const spans = await spansForSection('admonitions-block')
    expect(hasClass(spans, 'adoc-admonition-label')).toBe(true)
    expect(hasClass(spans, 'adoc-delimiter')).toBe(true)
  })

  it('highlights document header author and revision lines in the full fixture', async () => {
    clearParseCache()
    const spans = await refreshHighlights(SYNTAX_QUICK_REFERENCE)
    expect(hasClass(spans, 'adoc-document-header')).toBe(true)
  })
})
