import { describe, expect, it } from 'vitest'
import { configureVanillaHost } from '../vanilla_host.js'
import {
  extractWikiLinkTargets,
  substituteWikiLinksForPreview,
} from '../src/wiki_link_substitute.js'

configureVanillaHost()

describe('substituteWikiLinksForPreview', () => {
  it('replaces unresolved ASCII-only targets with broken-link markup', () => {
    const out = substituteWikiLinksForPreview('See [[second-memo]].', new Map())
    expect(out).toBe('See [.memo-wiki-broken]#second-memo#.')
    expect(out).not.toContain('[[second-memo]]')
  })

  it('replaces unresolved CJK targets with broken-link markup', () => {
    const out = substituteWikiLinksForPreview('See [[テスト]].', new Map())
    expect(out).toBe('See [.memo-wiki-broken]#テスト#.')
  })

  it('resolves targets from the labels map using memo_uid', () => {
    const uid = '01KDWPVPF8KRVQ2FP8BPQCZ4VZ'
    const labels = new Map([
      ['second-memo', { resolved: true, slug: true, memo_id: 42, memo_uid: uid, display: 'Second memo' }],
    ])
    const out = substituteWikiLinksForPreview('See [[second-memo]].', labels)
    expect(out).toBe(`See link:/memos/${uid}[Second memo].`)
  })

  it('falls back to memo_id when memo_uid is absent', () => {
    const labels = new Map([
      ['second-memo', { resolved: true, slug: true, memo_id: 42, display: 'Second memo' }],
    ])
    const out = substituteWikiLinksForPreview('See [[second-memo]].', labels)
    expect(out).toBe('See link:/memos/42[Second memo].')
  })

  it('keeps custom labels on unresolved links', () => {
    const out = substituteWikiLinksForPreview('[[target|short]]', new Map())
    expect(out).toBe('[.memo-wiki-broken]#short#')
  })

  it('skips wiki links inside fenced code blocks', () => {
    const source = '```\n[[ignored]]\n```\n[[shown]]'
    expect(extractWikiLinkTargets(source)).toEqual(['shown'])
    const out = substituteWikiLinksForPreview(source, new Map())
    expect(out).toContain('[[ignored]]')
    expect(out).toContain('[.memo-wiki-broken]#shown#')
  })
})
