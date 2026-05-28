import { describe, expect, it } from 'vitest'
import { asciidocBlockToHtml, parseEditUnitsFromSource } from '../index.js'

describe('parseEditUnitsFromSource', () => {
  it('splits paragraphs into edit units', () => {
    const source = '= Title\n\nFirst paragraph.\n\nSecond paragraph.'
    const units = parseEditUnitsFromSource(source)

    expect(units.length).toBeGreaterThan(1)
    expect(units.some((unit) => unit.adoc.includes('First paragraph'))).toBe(true)
    expect(units.some((unit) => unit.adoc.includes('Second paragraph'))).toBe(true)
  })

  it('keeps source-paragraph attribute line and body in one edit unit', () => {
    const source = `[source,xml]
<meta name="viewport"
  content="width=device-width, initial-scale=1.0">

This is normal content.`
    const units = parseEditUnitsFromSource(source)
    const sourceUnit = units.find((unit) => unit.adoc.includes('<meta name="viewport"'))

    expect(sourceUnit).toBeDefined()
    expect(sourceUnit?.adoc).toMatch(/^\[source,xml\]/m)
    expect(sourceUnit?.adoc).toContain('initial-scale=1.0')
    expect(units.some((unit) => unit.adoc.trim() === '[source,xml]')).toBe(false)
    expect(units.some((unit) => unit.adoc.includes('This is normal content'))).toBe(true)
  })

  it('renders source-paragraph units as listing blocks in WYSIWYG preview', () => {
    const source = `[source,xml]
<meta name="viewport"
  content="width=device-width, initial-scale=1.0">`
    const unit = parseEditUnitsFromSource(source)[0]
    const html = asciidocBlockToHtml(unit.adoc)

    expect(unit.adoc).toMatch(/^\[source,xml\]/m)
    expect(html).toContain('listingblock')
    expect(html).toContain('language-xml')
    expect(html).not.toContain('class="paragraph"')
  })

  it('keeps optional title with source-paragraph in one edit unit', () => {
    const source = `.Viewport snippet
[source,xml]
<meta name="viewport">`
    const units = parseEditUnitsFromSource(source)
    const sourceUnit = units.find((unit) => unit.adoc.includes('<meta name="viewport"'))

    expect(sourceUnit?.adoc).toMatch(/^\.Viewport snippet\n\[source,xml\]/m)
    expect(asciidocBlockToHtml(sourceUnit?.adoc ?? '')).toContain('listingblock')
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
