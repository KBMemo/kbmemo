// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { clearParseCache, refreshHighlights } from '../index.js'
import {
  extractSyntaxRefSections,
  SYNTAX_QUICK_REFERENCE,
} from '@kbmemo/test-fixtures'

/** @param {string} id */
function spansForSection(id) {
  clearParseCache()
  const section = extractSyntaxRefSections(SYNTAX_QUICK_REFERENCE).find((entry) => entry.id === id)
  if (!section) throw new Error(`missing syntax-ref section: ${id}`)
  return refreshHighlights(section.adoc)
}

/** @param {ReturnType<typeof refreshHighlights>} spans @param {string} className */
function hasClass(spans, className) {
  return spans.some((span) => span.className.includes(className))
}

describe('Phase D syntax highlighting', () => {
  it('highlights inline and positioned image macros', () => {
    const inlineSpans = spansForSection('images-inline')
    expect(hasClass(inlineSpans, 'adoc-image-marker')).toBe(true)
    expect(hasClass(inlineSpans, 'adoc-image-target')).toBe(true)

    const positionedSpans = spansForSection('images-positioning')
    expect(hasClass(positionedSpans, 'adoc-image-alt')).toBe(true)
  })

  it('highlights audio and video macros', () => {
    const audioSpans = spansForSection('audio')
    expect(hasClass(audioSpans, 'adoc-audio-marker')).toBe(true)
    expect(hasClass(audioSpans, 'adoc-audio-target')).toBe(true)

    const videoSpans = spansForSection('video')
    expect(hasClass(videoSpans, 'adoc-video-marker')).toBe(true)
    expect(hasClass(videoSpans, 'adoc-video-target')).toBe(true)
  })

  it('highlights kbd, menu, and btn macros', () => {
    const spans = spansForSection('macros-kbd-menu-btn')
    expect(hasClass(spans, 'adoc-kbd')).toBe(true)
    expect(hasClass(spans, 'adoc-menu')).toBe(true)
    expect(hasClass(spans, 'adoc-button')).toBe(true)
  })

  it('highlights footnotes in paragraphs', () => {
    const spans = spansForSection('footnotes')
    expect(hasClass(spans, 'adoc-footnote')).toBe(true)
  })

  it('highlights bibliography cross references', () => {
    const spans = spansForSection('bibliography')
    expect(hasClass(spans, 'adoc-xref')).toBe(true)
    expect(hasClass(spans, 'adoc-anchor')).toBe(true)
  })
})
