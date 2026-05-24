import { describe, expect, it } from 'vitest'

describe('@kbmemo/adoc-codemirror dist bundle', () => {
  it('exports highlight helpers from dist/index.js', async () => {
    const mod = await import('../dist/index.js')

    expect(typeof mod.refreshHighlights).toBe('function')
    expect(typeof mod.parseEditUnitsFromSource).toBe('function')
    expect(Array.isArray(mod.asciidocHighlight)).toBe(true)
  })
})
