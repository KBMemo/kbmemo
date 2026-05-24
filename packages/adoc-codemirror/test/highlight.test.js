import { beforeEach, describe, expect, it } from 'vitest'
import { clearParseCache, refreshHighlights } from '../index.js'

describe('refreshHighlights', () => {
  beforeEach(() => {
    clearParseCache()
  })

  it('returns heading highlight spans', () => {
    const source = '= Section title\n\nPlain paragraph.'
    const spans = refreshHighlights(source)

    expect(spans.length).toBeGreaterThan(0)
    expect(spans.some((span) => span.className.includes('adoc-heading'))).toBe(true)
  })

  it('reuses cached highlights for unchanged source', () => {
    const source = '* list item'
    const first = refreshHighlights(source)
    const second = refreshHighlights(source)

    expect(second).toBe(first)
  })
})
