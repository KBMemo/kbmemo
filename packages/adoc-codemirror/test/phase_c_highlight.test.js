// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { clearParseCache, refreshHighlights } from '../index.js'
import {
  extractSyntaxRefSections,
  wrapSyntaxRefSection,
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

describe('Phase C syntax highlighting', () => {
  it('highlights unconstrained emphasis and monospace', async () => {
    const spans = await spansForSection('text-formatting-unconstrained')
    expect(hasClass(spans, 'adoc-emphasis')).toBe(true)
    expect(hasClass(spans, 'adoc-strong')).toBe(true)
    expect(hasClass(spans, 'adoc-monospace')).toBe(true)
  })

  it('highlights marked and role-based text', async () => {
    const spans = await spansForSection('text-formatting-highlight')
    expect(hasClass(spans, 'adoc-highlight')).toBe(true)
  })

  it('highlights superscript and subscript', async () => {
    const spans = await spansForSection('text-formatting-super-sub')
    expect(hasClass(spans, 'adoc-superscript')).toBe(true)
    expect(hasClass(spans, 'adoc-subscript')).toBe(true)
  })

  it('highlights anchors and cross references', async () => {
    const spans = await spansForSection('links-anchors')
    expect(hasClass(spans, 'adoc-anchor')).toBe(true)

    const xrefSpans = await spansForSection('links-xref')
    expect(hasClass(xrefSpans, 'adoc-xref')).toBe(true)

    const interdocSpans = await spansForSection('links-interdoc')
    expect(hasClass(interdocSpans, 'adoc-xref')).toBe(true)
  })

  it('highlights literal paragraphs without delimiter noise', async () => {
    const spans = await spansForSection('paragraphs-literal')
    expect(hasClass(spans, 'adoc-literal')).toBe(true)
    expect(spans.some((span) => span.className === 'adoc-delimiter')).toBe(false)
  })

  it('highlights hard line breaks', async () => {
    clearParseCache()
    const spans = await refreshHighlights(wrapSyntaxRefSection('Roses are red, +\nviolets are blue.'))
    expect(hasClass(spans, 'adoc-hardbreak')).toBe(true)
  })
})
