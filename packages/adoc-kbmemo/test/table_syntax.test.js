import { describe, expect, it } from 'vitest'
import { isTableAttrLine, isTableDelimiterLine } from '../index.js'

describe('table_syntax', () => {
  it('detects table delimiters and attribute lines', () => {
    expect(isTableDelimiterLine('|===')).toBe(true)
    expect(isTableDelimiterLine(',===')).toBe(true)
    expect(isTableDelimiterLine(':===')).toBe(true)
    expect(isTableAttrLine('[cols="1,2"]')).toBe(true)
    expect(isTableAttrLine('[source,ruby]')).toBe(false)
  })
})
