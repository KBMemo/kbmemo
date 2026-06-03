// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { webHtmlToAsciidoc } from '../src/webHtmlToAsciidoc.js'

describe('webHtmlToAsciidoc linked images', () => {
  it('converts linked badge image to image macro with link attribute', () => {
    const html = `
      <p>
        <a href="https://github.com/WaveSpeedAI/wavespeed-desktop/releases/latest">
          <img src="https://camo.githubusercontent.com/badge.png" alt="GitHub Release">
        </a>
      </p>
    `

    const adoc = webHtmlToAsciidoc(html)

    expect(adoc).toBe(
      'image:https://camo.githubusercontent.com/badge.png[GitHub Release, link=https://github.com/WaveSpeedAI/wavespeed-desktop/releases/latest]'
    )
    expect(adoc).not.toContain('link:https://camo.githubusercontent.com')
  })
})
