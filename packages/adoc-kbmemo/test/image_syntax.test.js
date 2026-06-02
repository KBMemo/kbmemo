import { describe, expect, it } from 'vitest'
import {
  appImageSrc,
  memoAssetRelativePath,
  memoAssetSrc,
  normalizeMemoImagePathsInSource,
  stripPseudoImageUriScheme,
} from '../src/image_syntax.js'

describe('stripPseudoImageUriScheme', () => {
  it('strips macros: prefix from image filenames', () => {
    expect(stripPseudoImageUriScheme('macros:sunset.jpg')).toBe('sunset.jpg')
  })

  it('leaves https URLs unchanged', () => {
    expect(stripPseudoImageUriScheme('https://example.com/a.png')).toBe('https://example.com/a.png')
  })
})

describe('normalizeMemoImagePathsInSource pseudo URI scheme', () => {
  it('rewrites image macro with macros: path', () => {
    const source = '[#img,caption="Figure 1: ",link=https://example.com/]\nimage::macros:sunset.jpg[Sunset,200,100]'
    expect(normalizeMemoImagePathsInSource(source, 14)).toBe(
      '[#img,caption="Figure 1: ",link=https://example.com/]\nimage::sunset.jpg[Sunset,200,100]',
    )
  })
})

describe('appImageSrc', () => {
  it('maps /images/filename to app image route', () => {
    expect(appImageSrc('/images/octocat.jpg')).toBe('/images/octocat.jpg')
    expect(appImageSrc('images/octocat.jpg')).toBe('/images/octocat.jpg')
  })

  it('leaves memo asset paths unchanged', () => {
    expect(appImageSrc('box.png')).toBeNull()
    expect(appImageSrc('/memos/14/assets/box.png')).toBeNull()
  })
})

describe('memoAssetRelativePath', () => {
  it('maps memo asset URL to relative path', () => {
    expect(memoAssetRelativePath(14, '/memos/14/assets/box.png')).toBe('box.png')
  })

  it('does not rewrite /images paths to memo assets', () => {
    expect(memoAssetRelativePath(1, '/images/octocat.jpg')).toBe('/images/octocat.jpg')
  })

  it('builds memo asset URL for flat filename', () => {
    expect(memoAssetSrc(14, 'box.png')).toBe('/memos/14/assets/box.png')
  })

  it('does not treat /images as memo asset', () => {
    expect(memoAssetSrc(14, '/images/octocat.jpg')).toBeNull()
  })
})

describe('normalizeMemoImagePathsInSource', () => {
  it('rewrites memo asset URL in image macro', () => {
    const source = 'image::/memos/14/assets/box.png[Alt text]'
    expect(normalizeMemoImagePathsInSource(source, 14)).toBe('image::box.png[Alt text]')
  })

  it('leaves /images app asset paths unchanged', () => {
    const source = 'image::/images/octocat.jpg[GitHub mascot]'
    expect(normalizeMemoImagePathsInSource(source, 14)).toBe(source)
  })

  it('leaves Tsuzura signed URLs unchanged', () => {
    const url =
      'http://localhost:3008/v1/media/01KT2V6A22B7XC915A3B3V1ADF/web?memo_id=14&exp=999&sig=abc'
    const source = `image::${url}[photo]`
    expect(normalizeMemoImagePathsInSource(source, 14)).toBe(source)
  })
})
