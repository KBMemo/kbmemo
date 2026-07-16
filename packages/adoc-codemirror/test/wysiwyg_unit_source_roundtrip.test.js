// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { asciidocBlockToHtml } from '../index.js'
import { htmlToAsciidoc, unitToAsciidoc } from '../src/htmlToAsciidoc.js'
import { setUnitAdocSource } from '../../adoc-wysiwyg/wysiwyg_unit_source.js'

async function wysiwygUnitWithPreview(adoc) {
  const unit = document.createElement('div')
  unit.className = 'wysiwyg-unit'
  const temp = document.createElement('div')
  temp.innerHTML = await asciidocBlockToHtml(adoc)
  unit.replaceChildren(...temp.childNodes)
  setUnitAdocSource(unit, adoc)
  return unit
}

describe('wysiwyg-unit uses stored AsciiDoc source', () => {
  it('unitToAsciidoc returns stored source instead of preview HTML', async () => {
    const adoc = 'Roses are red, +\nviolets are blue.'
    const unit = await wysiwygUnitWithPreview(adoc)
    expect(unitToAsciidoc(unit)).toBe(adoc)
  })

  it('htmlToAsciidoc preserves hard break markers from stored source', async () => {
    const adoc = '[%hardbreaks]\nA ruby is red.\nJava is black.'
    const root = document.createElement('div')
    root.append(await wysiwygUnitWithPreview(adoc))
    expect(htmlToAsciidoc(root).trim()).toBe(adoc)
  })

  it('htmlToAsciidoc preserves [.lead] from stored source', async () => {
    const adoc = '[.lead]\nIntro paragraph.'
    const root = document.createElement('div')
    root.append(await wysiwygUnitWithPreview(adoc))
    expect(htmlToAsciidoc(root).trim()).toBe(adoc)
  })

  it('returns empty string when wysiwyg-unit has no stored source', () => {
    const unit = document.createElement('div')
    unit.className = 'wysiwyg-unit'
    unit.innerHTML = '<div class="paragraph"><p>Preview only</p></div>'
    expect(unitToAsciidoc(unit)).toBe('')
  })
})
