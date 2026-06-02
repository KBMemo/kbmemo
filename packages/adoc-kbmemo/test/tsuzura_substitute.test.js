import { describe, expect, it } from 'vitest'
import {
  extractTsuzuraAlbumIds,
  extractTsuzuraMediaIds,
  substituteTsuzuraForPreview,
} from '../src/tsuzura_substitute.js'

const MEDIA_ULID = '01JH0000000000000000000001'
const ALBUM_ULID = '01JH0000000000000000000002'
const OTHER_ULID = '01JH0000000000000000000003'

describe('substituteTsuzuraForPreview', () => {
  it('expands image::media: to signed image URL', () => {
    const urls = new Map([[MEDIA_ULID, 'https://media.example/v1/web']])
    const out = substituteTsuzuraForPreview(`image::media:${MEDIA_ULID}[width=720]`, { urls })
    expect(out).toBe('image::https://media.example/v1/web[width=720]')
  })

  it('expands album:: line to multiple images', () => {
    const urls = new Map([
      [MEDIA_ULID, 'https://media.example/1'],
      [OTHER_ULID, 'https://media.example/2'],
    ])
    const albums = new Map([[ALBUM_ULID, [MEDIA_ULID, OTHER_ULID]]])
    const out = substituteTsuzuraForPreview(`album::${ALBUM_ULID}[]`, { urls, albums })
    expect(out).toBe(
      `image::https://media.example/1[]\nimage::https://media.example/2[]`,
    )
  })

  it('skips macros inside fenced code blocks', () => {
    const source = ['```', `image::media:${MEDIA_ULID}[]`, '```'].join('\n')
    const urls = new Map([[MEDIA_ULID, 'https://media.example/v1/web']])
    expect(substituteTsuzuraForPreview(source, { urls })).toBe(source)
  })

  it('extracts media and album ids from source', () => {
    const source = `album::${ALBUM_ULID}[]\nimage::media:${MEDIA_ULID}[]`
    expect(extractTsuzuraAlbumIds(source)).toEqual([ALBUM_ULID])
    expect(extractTsuzuraMediaIds(source)).toEqual([MEDIA_ULID])
  })

  it('re-signs legacy localhost tsuzura image urls', () => {
    const legacy =
      `image::http://localhost:3008/v1/media/${MEDIA_ULID}/web?memo_id=70&exp=1&sig=abc[]`
    const urls = new Map([[MEDIA_ULID, 'https://media.kbmemo.net/v1/web']])
    const out = substituteTsuzuraForPreview(legacy, { urls })
    expect(out).toBe('image::https://media.kbmemo.net/v1/web[]')
    expect(out).not.toContain('localhost:3008')
  })
})
