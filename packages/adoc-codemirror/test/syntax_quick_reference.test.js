// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import {
  clearParseCache,
  parseEditUnitsFromSource,
  refreshHighlights,
} from '../index.js'
import {
  SYNTAX_QUICK_REFERENCE,
  SYNTAX_QUICK_REFERENCE_IDS,
} from '@kbmemo/test-fixtures'

describe('syntax-quick-reference.adoc fixture', () => {
  it('lists syntax-ref section markers', () => {
    expect(SYNTAX_QUICK_REFERENCE_IDS.length).toBeGreaterThan(60)
    expect(SYNTAX_QUICK_REFERENCE_IDS).toContain('paragraphs')
    expect(SYNTAX_QUICK_REFERENCE_IDS).toContain('tables-basic')
    expect(SYNTAX_QUICK_REFERENCE_IDS).toContain('kbmemo-wiki')
  })

  it('parses highlights without throwing', () => {
    clearParseCache()
    const spans = refreshHighlights(SYNTAX_QUICK_REFERENCE)
    expect(spans.length).toBeGreaterThan(0)
  })

  it('splits edit units without throwing', () => {
    const units = parseEditUnitsFromSource(SYNTAX_QUICK_REFERENCE)
    expect(units.length).toBeGreaterThan(10)
    expect(units.every((unit) => typeof unit.adoc === 'string')).toBe(true)
  })
})
