import { beforeEach, describe, expect, it } from 'vitest'
import { clearParseCache, refreshHighlights } from '../index.js'

describe('refreshHighlights', () => {
  beforeEach(() => {
    clearParseCache()
  })

  it('returns heading highlight spans', async () => {
    const source = '= Section title\n\nPlain paragraph.'
    const spans = await refreshHighlights(source)

    expect(spans.length).toBeGreaterThan(0)
    expect(spans.some((span) => span.className.includes('adoc-heading'))).toBe(true)
  })

  it('reuses cached highlights for unchanged source', async () => {
    const source = '* list item'
    const first = await refreshHighlights(source)
    const second = await refreshHighlights(source)

    expect(second).toBe(first)
  })
})
