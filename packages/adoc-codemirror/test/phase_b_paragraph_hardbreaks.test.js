// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { asciidocBlockToHtml } from '../src/blockConvert.js'
import { htmlToAsciidoc } from '../src/htmlToAsciidoc.js'
import { parseEditUnitsFromSource } from '../index.js'
import {
  extractSyntaxRefSections,
  SYNTAX_QUICK_REFERENCE,
} from '@kbmemo/test-fixtures'

/** @param {string} body */
function unitsForBody(body) {
  return parseEditUnitsFromSource(`= Title\n\n${body}`).filter((unit) => unit.startLine >= 2)
}

/** @param {string} id */
function sectionBody(id) {
  const section = extractSyntaxRefSections(SYNTAX_QUICK_REFERENCE).find((entry) => entry.id === id)
  if (!section) throw new Error(`missing syntax-ref section: ${id}`)
  return section.body
}

describe('Phase B paragraph hard breaks', () => {
  it('keeps [%hardbreaks] paragraph in one unit', () => {
    const units = unitsForBody(sectionBody('paragraphs-hardbreaks'))
    const hardbreakUnit = units.find((unit) => unit.adoc.includes('A ruby is red.'))
    expect(hardbreakUnit).toBeDefined()
    expect(hardbreakUnit.adoc).toContain('[%hardbreaks]')
    expect(hardbreakUnit.adoc).toContain('Java is black.')
    expect(units.some((unit) => unit.adoc.trim() === '[%hardbreaks]')).toBe(false)
  })

  it('keeps line-ending plus hard break paragraph in one unit', () => {
    const units = unitsForBody(sectionBody('paragraphs-hardbreaks'))
    const plusUnit = units.find((unit) => unit.adoc.includes('Roses are red,'))
    expect(plusUnit).toBeDefined()
    expect(plusUnit.adoc).toContain('Roses are red, +')
    expect(plusUnit.adoc).toContain('violets are blue.')
  })

  it('round-trips line-ending plus through preview html', () => {
    const adoc = 'Roses are red, +\nviolets are blue.'
    const html = asciidocBlockToHtml(adoc)
    const wrapper = document.createElement('div')
    wrapper.innerHTML = html
    const paragraph = wrapper.querySelector('.paragraph')
    expect(paragraph).toBeTruthy()
    expect(htmlToAsciidoc(wrapper).trim()).toBe(adoc)
  })

  it('round-trips [%hardbreaks] through preview html', () => {
    const adoc = '[%hardbreaks]\nA ruby is red.\nJava is black.'
    const html = asciidocBlockToHtml(adoc)
    const wrapper = document.createElement('div')
    wrapper.innerHTML = html
    const paragraph = wrapper.querySelector('.paragraph')
    expect(paragraph).toBeTruthy()
    paragraph.dataset.kbHardbreaks = 'true'
    expect(htmlToAsciidoc(wrapper).trim()).toBe(adoc)
  })
})
