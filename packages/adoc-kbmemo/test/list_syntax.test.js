import { describe, expect, it } from 'vitest'
import { listContinuationInsert, parseListLine } from '../src/list_syntax.js'

describe('parseListLine checklist', () => {
  it('parses dash checklist items', () => {
    const parsed = parseListLine('- [ ] unchecked task')
    expect(parsed).not.toBeNull()
    expect(parsed.marker).toBe('-')
    expect(parsed.checklistMarker).toBe('[ ]')
    expect(parsed.content).toBe('unchecked task')
  })

  it('parses asterisk checked checklist items', () => {
    const parsed = parseListLine('* [x] done')
    expect(parsed?.checklistMarker).toBe('[x]')
    expect(parsed?.content).toBe('done')
  })

  it('inserts unchecked checklist marker on continuation', () => {
    const parsed = parseListLine('- [ ] first')
    const doc = { line: (n) => ({ text: n === 1 ? '- [ ] first' : '' }) }
    expect(listContinuationInsert(doc, 1, parsed)).toBe('\n- [ ] ')
  })

  it('keeps plain bullet continuation without checklist marker', () => {
    const parsed = parseListLine('- plain item')
    const doc = { line: (n) => ({ text: n === 1 ? '- plain item' : '' }) }
    expect(listContinuationInsert(doc, 1, parsed)).toBe('\n- ')
  })
})
