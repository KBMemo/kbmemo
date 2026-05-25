import { describe, expect, it } from 'vitest'
import { captureInlines, findInlineMarkup, inlineClassName } from '../src/inlineCapture.js'
import { loadDocument } from '../src/instance.js'

/** @param {string} body */
function inlineForBody(body) {
  const doc = loadDocument(`= Title\n\n${body}`)
  const paragraph = doc.findBy({ context: 'paragraph' })[0]
  const text = paragraph.getSource()
  const captured = captureInlines(paragraph, text)
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

  it('finds highlight and superscript markup', () => {
    const highlight = inlineForBody('Mark my words, #automation is essential#.')
    expect(findInlineMarkup(highlight.text, highlight.inline)).toEqual({
      from: 15,
      to: 40,
    })

    const superscript = inlineForBody('^super^script')
    expect(findInlineMarkup(superscript.text, superscript.inline)).toEqual({
      from: 0,
      to: 7,
    })
  })

  it('finds anchor and inter-document xref markup', () => {
    const anchor = inlineForBody('[[bookmark-a]]Inline anchors make arbitrary content referenceable.')
    expect(findInlineMarkup(anchor.text, anchor.inline)).toEqual({
      from: 0,
      to: 14,
    })

    const interdoc = inlineForBody('Refer to xref:other-document.adoc#section-b[Section B] for more information.')
    expect(findInlineMarkup(interdoc.text, interdoc.inline)).toEqual({
      from: 9,
      to: 54,
    })
  })

  it('finds btn and footnote markup', () => {
    const button = inlineForBody('Press the btn:[OK] button.')
    expect(findInlineMarkup(button.text, button.inline)).toEqual({
      from: 10,
      to: 18,
    })

    const footnote = inlineForBody('A statement.footnote:[Clarification about this statement.]')
    expect(findInlineMarkup(footnote.text, footnote.inline)).toEqual({
      from: 12,
      to: 58,
    })
  })
})
