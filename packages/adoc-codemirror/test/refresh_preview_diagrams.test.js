import { beforeEach, describe, expect, it } from 'vitest'
import { configureVanillaHost } from '@kbmemo/adoc-kbmemo'
import { clearParseCache, refreshPreview } from '../src/parseSession.js'

configureVanillaHost()

describe('refreshPreview diagrams', () => {
  beforeEach(() => {
    clearParseCache()
  })

  it('does not render a memo asset image when the diagram svg is unavailable', async () => {
    const { html } = await refreshPreview('diagram::flow.mmd[]', {
      memoId: '1',
      diagramAvailability: new Map([['diagrams/flow.svg', false]]),
    })

    expect(html).toContain('memo-diagram-missing')
    expect(html).toContain('diagrams/flow.svg')
    expect(html).not.toContain('/memos/1/assets/diagrams/flow.svg')
  })

  it('rebuilds cached preview when diagram availability changes', async () => {
    await refreshPreview('diagram::flow.mmd[]', {
      memoId: '1',
      diagramAvailability: new Map([['diagrams/flow.svg', false]]),
    })

    const { html } = await refreshPreview('diagram::flow.mmd[]', {
      memoId: '1',
      diagramAvailability: new Map([['diagrams/flow.svg', true]]),
    })

    expect(html).toContain('src="diagrams/flow.svg"')
    expect(html).not.toContain('memo-diagram-missing')
  })
})
