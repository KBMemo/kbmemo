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
async function unitsForBody(body) {
  return (await parseEditUnitsFromSource(`= Title\n\n${body}`)).filter((unit) => unit.startLine >= 2)
}

/** @param {string} id */
function sectionBody(id) {
  const section = extractSyntaxRefSections(SYNTAX_QUICK_REFERENCE).find((entry) => entry.id === id)
  if (!section) throw new Error(`missing syntax-ref section: ${id}`)
  return section.body
}

describe('Phase B lead paragraphs', () => {
  it('keeps [.lead] attribute with paragraph body in one unit', async () => {
    const units = await unitsForBody(sectionBody('paragraphs-lead'))
    const leadUnit = units.find((unit) => unit.adoc.includes('lead paragraph'))
    expect(leadUnit).toBeDefined()
    expect(leadUnit.adoc).toContain('[.lead]')
    expect(leadUnit.adoc).toContain('This text will be styled as a lead paragraph')
    expect(units.some((unit) => unit.adoc.trim() === '[.lead]')).toBe(false)
  })

  it('round-trips [.lead] through preview html', async () => {
    const adoc = '[.lead]\nThis text will be styled as a lead paragraph (i.e., larger font).'
    const html = await asciidocBlockToHtml(adoc)
    const wrapper = document.createElement('div')
    wrapper.innerHTML = html
    expect(wrapper.querySelector('.paragraph.lead')).toBeTruthy()
    expect(htmlToAsciidoc(wrapper).trim()).toBe(adoc)
  })

  it('round-trips [.lead] using preview dataset annotation', async () => {
    const adoc = '[.lead]\nLead body text.'
    const html = await asciidocBlockToHtml('Plain paragraph.\n\n' + adoc)
    const wrapper = document.createElement('div')
    wrapper.innerHTML = html
    const leadParagraph = wrapper.querySelector('.paragraph.lead')
    expect(leadParagraph).toBeTruthy()
    leadParagraph.dataset.kbLead = 'true'
    expect(htmlToAsciidoc(wrapper).trim()).toBe(`Plain paragraph.\n\n${adoc}`)
  })
})
