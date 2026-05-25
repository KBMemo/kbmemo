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
  SYNTAX_QUICK_REFERENCE_SECTIONS,
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

  it('parses highlights for every syntax-ref section', () => {
    clearParseCache()
    const failures = []

    for (const section of SYNTAX_QUICK_REFERENCE_SECTIONS) {
      try {
        refreshHighlights(section.adoc)
      } catch (error) {
        failures.push({ id: section.id, layer: 'HL', error })
      }
    }

    expect(failures, formatSectionFailures(failures)).toEqual([])
  })

  it('splits edit units for every syntax-ref section', () => {
    const failures = []

    for (const section of SYNTAX_QUICK_REFERENCE_SECTIONS) {
      try {
        const units = parseEditUnitsFromSource(section.adoc)
        if (!units.every((unit) => typeof unit.adoc === 'string')) {
          failures.push({ id: section.id, layer: 'EU', error: 'invalid unit shape' })
        }
      } catch (error) {
        failures.push({ id: section.id, layer: 'EU', error })
      }
    }

    expect(failures, formatSectionFailures(failures)).toEqual([])
  })
})

/** @param {{ id: string, layer: string, error: unknown }[]} failures */
function formatSectionFailures(failures) {
  return failures
    .map(({ id, layer, error }) => {
      const message = error instanceof Error ? error.message : String(error)
      return `${id} (${layer}): ${message}`
    })
    .join('\n')
}
