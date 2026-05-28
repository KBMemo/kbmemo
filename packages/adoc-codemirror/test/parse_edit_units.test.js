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

  it('keeps source listings and callout footnotes in one edit unit', () => {
    const source = `= Title

[source,ruby]
----
require 'sinatra' // <1>
----
<1> Library import
<2> URL mapping
`
    const units = parseEditUnitsFromSource(source)
    const listingUnit = units.find((unit) => unit.adoc.includes("require 'sinatra'"))

    expect(listingUnit).toBeDefined()
    expect(listingUnit?.adoc).toContain('<1> Library import')
    expect(listingUnit?.adoc).toContain('<2> URL mapping')
    expect(units.some((unit) => unit.adoc.trim() === '<1> Library import')).toBe(false)
  })
})
