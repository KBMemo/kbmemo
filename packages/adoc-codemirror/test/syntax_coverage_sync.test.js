import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import {
  ROADMAP_PATH,
  SYNTAX_QUICK_REFERENCE_IDS,
  parseRoadmapSyntaxRefIds,
} from '@kbmemo/test-fixtures'

describe('syntax coverage fixture ↔ roadmap sync', () => {
  it('lists the same syntax-ref ids in fixture and roadmap table', () => {
    const roadmapSource = readFileSync(ROADMAP_PATH, 'utf8')
    const roadmapIds = parseRoadmapSyntaxRefIds(roadmapSource)

    expect(new Set(SYNTAX_QUICK_REFERENCE_IDS)).toEqual(new Set(roadmapIds))
    expect(SYNTAX_QUICK_REFERENCE_IDS.length).toBe(roadmapIds.length)
  })
})
