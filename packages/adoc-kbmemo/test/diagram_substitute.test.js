import { afterEach, describe, expect, it, vi } from 'vitest'
import { configureVanillaHost } from '../vanilla_host.js'
import {
  diagramAvailabilityCacheKey,
  ensureDiagramSvgsInCache,
  extractDiagramSvgRelativePaths,
  substituteDiagramsForPreview,
} from '../src/diagram_substitute.js'

configureVanillaHost()

afterEach(() => {
  vi.restoreAllMocks()
})

describe('substituteDiagramsForPreview', () => {
  it('renders missing markup when the diagram svg is unavailable', () => {
    const availability = new Map([['diagrams/flow.svg', false]])

    expect(substituteDiagramsForPreview('diagram::flow.mmd[]', availability)).toBe(
      '[.memo-diagram-missing]#diagrams/flow.svg#',
    )
  })

  it('renders interactive svg image when the diagram svg is available', () => {
    const availability = new Map([['diagrams/flow.svg', true]])

    expect(substituteDiagramsForPreview('diagram::flow.mmd[]', availability)).toBe(
      'image::diagrams/flow.svg[opts=interactive]',
    )
  })

  it('keeps legacy optimistic rendering when availability is omitted', () => {
    expect(substituteDiagramsForPreview('diagram::flow.mmd[]')).toBe(
      'image::diagrams/flow.svg[opts=interactive]',
    )
  })
})

describe('extractDiagramSvgRelativePaths', () => {
  it('extracts unique svg paths outside fenced code blocks', () => {
    const source = [
      '```',
      'diagram::ignored.mmd[]',
      '```',
      'diagram::flow.mmd[]',
      'See diagram::nested/flow.mmd[]',
      'diagram::flow.mmd[]',
    ].join('\n')

    expect(extractDiagramSvgRelativePaths(source)).toEqual([
      'diagrams/flow.svg',
      'diagrams/nested/flow.svg',
    ])
  })
})

describe('diagramAvailabilityCacheKey', () => {
  it('is stable across insertion order', () => {
    expect(
      diagramAvailabilityCacheKey(
        new Map([
          ['diagrams/z.svg', false],
          ['diagrams/a.svg', true],
        ]),
      ),
    ).toBe('diagrams/a.svg\t1\ndiagrams/z.svg\t0')
  })
})

describe('ensureDiagramSvgsInCache', () => {
  it('checks memo diagram svg availability with HEAD and caches the result', async () => {
    const fetchMock = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue({ ok: false })
    const cache = new Map()

    await ensureDiagramSvgsInCache(cache, 1, 'diagram::flow.mmd[]')
    await ensureDiagramSvgsInCache(cache, 1, 'diagram::flow.mmd[]')

    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(fetchMock).toHaveBeenCalledWith('/memos/1/assets/diagrams/flow.svg', {
      method: 'HEAD',
      credentials: 'same-origin',
      cache: 'no-store',
    })
    expect(cache.get('diagrams/flow.svg')).toBe(false)
  })
})
