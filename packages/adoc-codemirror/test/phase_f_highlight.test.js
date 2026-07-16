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

describe('Phase F syntax highlighting', () => {
  it('highlights checklist markers', async () => {
    expect(hasClass(await spansForSection('lists-checklist'), 'adoc-checklist-marker')).toBe(true)
  })

  it('highlights description and qanda list terms', async () => {
    expect(hasClass(await spansForSection('lists-description'), 'adoc-dlist-marker')).toBe(true)
    expect(hasClass(await spansForSection('lists-description'), 'adoc-dlist-term')).toBe(true)
    expect(hasClass(await spansForSection('lists-qanda'), 'adoc-qanda-label')).toBe(true)
    expect(hasClass(await spansForSection('lists-qanda'), 'adoc-dlist-marker')).toBe(true)
  })

  it('highlights bare email autolinks', async () => {
    expect(hasClass(await spansForSection('links-autolink'), 'adoc-link')).toBe(true)
  })

  it('highlights lead paragraphs', async () => {
    expect(hasClass(await spansForSection('paragraphs-lead'), 'adoc-lead')).toBe(true)
  })

  it('highlights text replacements and escapes', async () => {
    expect(hasClass(await spansForSection('text-replacements'), 'adoc-replacement')).toBe(true)
    expect(hasClass(await spansForSection('escaping'), 'adoc-escape')).toBe(true)
  })

  it('highlights markdown-style headings', async () => {
    const spans = await spansForSection('markdown-headings')
    expect(hasClass(spans, 'adoc-heading-marker')).toBe(true)
    expect(hasClass(spans, 'adoc-heading')).toBe(true)
  })

  it('highlights source callouts in listings and references', async () => {
    expect(hasClass(await spansForSection('source-callouts'), 'adoc-callout')).toBe(true)
  })

  it('highlights block titles and ids or roles', async () => {
    expect(hasClass(await spansForSection('blocks-sidebar'), 'adoc-block-title')).toBe(true)
    expect(hasClass(await spansForSection('ids-roles-options'), 'adoc-block-attribute')).toBe(true)
  })
})
