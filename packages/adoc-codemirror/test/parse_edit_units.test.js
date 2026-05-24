import { describe, expect, it } from 'vitest'
import { parseEditUnitsFromSource } from '../index.js'

describe('parseEditUnitsFromSource', () => {
  it('splits paragraphs into edit units', () => {
    const source = '= Title\n\nFirst paragraph.\n\nSecond paragraph.'
    const units = parseEditUnitsFromSource(source)

    expect(units.length).toBeGreaterThan(1)
    expect(units.some((unit) => unit.adoc.includes('First paragraph'))).toBe(true)
    expect(units.some((unit) => unit.adoc.includes('Second paragraph'))).toBe(true)
  })
})
