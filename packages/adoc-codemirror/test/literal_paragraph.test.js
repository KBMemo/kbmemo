import { describe, expect, it } from 'vitest'
import { asciidocBlockToHtml, parseEditUnitsFromSource } from '../index.js'
import {
  indentLiteralFromPlainText,
  isIndentLiteralBlock,
  normalizeBlockSegmentText,
  splitIndentLiteralAtBlankLine,
  splitParagraphAtBlankLine,
  indentForLiteralContinuation,
} from '../src/literalParagraph.js'

describe('indent literal paragraphs', () => {
  it('detects indent literal blocks by leading space', () => {
    expect(isIndentLiteralBlock(' A literal line.')).toBe(true)
    expect(isIndentLiteralBlock('A normal line.')).toBe(false)
    expect(isIndentLiteralBlock('....\nblock\n....')).toBe(false)
  })

  it('preserves leading space when normalizing block segments', () => {
    expect(normalizeBlockSegmentText(' A literal line.\n Second line.')).toBe(
      ' A literal line.\n Second line.',
    )
    expect(normalizeBlockSegmentText('A normal paragraph.\n')).toBe('A normal paragraph.')
    expect(normalizeBlockSegmentText('  Also indent literal.\n')).toBe('  Also indent literal.')
  })

  it('parseEditUnitsFromSource keeps indent on literal paragraph units', () => {
    const source = [
      'A normal paragraph.',
      '',
      ' A literal paragraph.',
      ' One or more consecutive lines indented by at least one space.',
    ].join('\n')

    const units = parseEditUnitsFromSource(source)
    const literalUnit = units.find((unit) => unit.adoc.includes('literal paragraph'))
    expect(literalUnit).toBeDefined()
    expect(literalUnit.adoc.startsWith(' A literal paragraph.')).toBe(true)
    expect(literalUnit.adoc).toContain('\n One or more consecutive lines')
  })

  it('asciidocBlockToHtml renders indent literals as literalblock', () => {
    const html = asciidocBlockToHtml(' A literal paragraph.')
    expect(html).toContain('literalblock')
    expect(html).not.toMatch(/class="paragraph"/)
  })

  it('indentLiteralFromPlainText prefixes each line with a space', () => {
    expect(indentLiteralFromPlainText('line one\nline two')).toBe(' line one\n line two')
  })

  it('splitIndentLiteralAtBlankLine separates literal content from following paragraph', () => {
    const source = '  line1\n  line2\n  \n'
    const { literalAdoc, afterAdoc } = splitIndentLiteralAtBlankLine(source, 2)
    expect(literalAdoc).toBe('  line1\n  line2')
    expect(afterAdoc).toBe('')
  })

  it('splitParagraphAtBlankLine separates normal paragraphs at a blank line', () => {
    const source = 'First paragraph.\n\n'
    const { beforeAdoc, afterAdoc } = splitParagraphAtBlankLine(source, 1)
    expect(beforeAdoc).toBe('First paragraph.')
    expect(afterAdoc).toBe('')
  })

  it('splitParagraphAtBlankLine keeps content after the blank line', () => {
    const source = 'First paragraph.\n\nSecond paragraph.'
    const { beforeAdoc, afterAdoc } = splitParagraphAtBlankLine(source, 1)
    expect(beforeAdoc).toBe('First paragraph.')
    expect(afterAdoc).toBe('Second paragraph.')
  })

  it('indentForLiteralContinuation reuses previous line indent', () => {
    const lines = ['  line1', '  line2']
    expect(indentForLiteralContinuation(lines, 1)).toBe('  ')
    expect(indentForLiteralContinuation(['  line1', ''], 1)).toBe('  ')
  })
})
