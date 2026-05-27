import { describe, expect, it } from 'vitest'
import {
  formatHardBreakLine,
  lineHasHardBreakContinuation,
} from '../src/hardbreakParagraph.js'

describe('hardbreakParagraph helpers', () => {
  it('detects trailing hard break marker on a line', () => {
    expect(lineHasHardBreakContinuation('Roses are red, +')).toBe(true)
    expect(lineHasHardBreakContinuation('Plain text')).toBe(false)
  })

  it('formats hard break lines without duplicating plus', () => {
    expect(formatHardBreakLine('Roses are red,')).toBe('Roses are red, +')
    expect(formatHardBreakLine('Roses are red, +')).toBe('Roses are red, +')
    expect(formatHardBreakLine('   ')).toBeNull()
  })
})
