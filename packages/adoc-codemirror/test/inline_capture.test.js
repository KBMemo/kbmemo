import { describe, expect, it } from 'vitest'
import { captureInlines, findInlineMarkup, inlineClassName } from '../src/inlineCapture.js'
import { loadDocument } from '../src/instance.js'

/** @param {string} body */
async function inlineForBody(body) {
  const doc = await loadDocument(`= Title\n\n${body}`)
  const paragraph = doc.findBy({ context: 'paragraph' })[0]
  const text = paragraph.getSource()
  const captured = await captureInlines(paragraph, text)
  return { text, inline: captured[0] }
}

describe('inlineCapture Phase C markup', () => {
  it('maps highlight and script styles to classes', () => {
    expect(inlineClassName({ context: 'quoted', type: 'mark' })).toBe('adoc-highlight')
    expect(inlineClassName({ context: 'quoted', type: 'superscript' })).toBe('adoc-superscript')
    expect(inlineClassName({ context: 'quoted', type: 'subscript' })).toBe('adoc-subscript')
    expect(inlineClassName({ context: 'anchor', type: 'ref' })).toBe('adoc-anchor')
    expect(inlineClassName({ context: 'anchor', type: 'xref' })).toBe('adoc-xref')
    expect(inlineClassName({ context: 'footnote' })).toBe('adoc-footnote')
  })

  it('finds highlight and superscript markup', async () => {
    const highlight = await inlineForBody('Mark my words, #automation is essential#.')
    expect(findInlineMarkup(highlight.text, highlight.inline)).toEqual({
      from: 15,
      to: 40,
    })

    const superscript = await inlineForBody('^super^script')
    expect(findInlineMarkup(superscript.text, superscript.inline)).toEqual({
      from: 0,
      to: 7,
    })
  })

  it('finds anchor and inter-document xref markup', async () => {
    const anchor = await inlineForBody('[[bookmark-a]]Inline anchors make arbitrary content referenceable.')
    expect(findInlineMarkup(anchor.text, anchor.inline)).toEqual({
      from: 0,
      to: 14,
    })

    const interdoc = await inlineForBody('Refer to xref:other-document.adoc#section-b[Section B] for more information.')
    expect(findInlineMarkup(interdoc.text, interdoc.inline)).toEqual({
      from: 9,
      to: 54,
    })
  })

  it('finds btn and footnote markup', async () => {
    const button = await inlineForBody('Press the btn:[OK] button.')
    expect(findInlineMarkup(button.text, button.inline)).toEqual({
      from: 10,
      to: 18,
    })

    const footnote = await inlineForBody('A statement.footnote:[Clarification about this statement.]')
    expect(findInlineMarkup(footnote.text, footnote.inline)).toEqual({
      from: 12,
      to: 58,
    })
  })

  it('serializes concurrent captureInlines calls without cross-contamination', async () => {
    const [strong, emphasis] = await Promise.all([
      inlineForBody('*strong text*'),
      inlineForBody('_emphasis text_'),
    ])

    expect(strong.inline.type).toBe('strong')
    expect(findInlineMarkup(strong.text, strong.inline)).toEqual({ from: 0, to: 13 })

    expect(emphasis.inline.type).toBe('emphasis')
    expect(findInlineMarkup(emphasis.text, emphasis.inline)).toEqual({ from: 0, to: 15 })
  })
})
