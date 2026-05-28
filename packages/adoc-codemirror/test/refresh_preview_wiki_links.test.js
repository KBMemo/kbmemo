import { describe, expect, it, beforeEach } from 'vitest'
import { configureVanillaHost } from '@kbmemo/adoc-kbmemo'
import { clearParseCache, refreshPreview } from '../src/parseSession.js'

configureVanillaHost()

describe('refreshPreview wiki links', () => {
  beforeEach(() => {
    clearParseCache()
  })

  it('renders ASCII-only unresolved wiki link labels', () => {
    const { html } = refreshPreview('See [[second-memo]].', {
      wikiLabels: new Map(),
    })
    expect(html).toContain('memo-wiki-broken')
    expect(html).toContain('second-memo')
    expect(html).not.toContain('[[second-memo]]')
  })

  it('renders resolved wiki links as memo hrefs', () => {
    const labels = new Map([
      ['second-memo', { resolved: true, slug: true, memo_id: 7, display: 'Second memo' }],
    ])
    const { html } = refreshPreview('See [[second-memo]].', { wikiLabels: labels })
    expect(html).toContain('href="/memos/7"')
    expect(html).toContain('Second memo')
  })
})
