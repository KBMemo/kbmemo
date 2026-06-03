// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { webHtmlToAsciidoc } from '../src/webHtmlToAsciidoc.js'

describe('webHtmlToAsciidoc github clip artifacts', () => {
  it('drops heading permalink anchors that only contain svg', () => {
    const html = `
      <h2>
        <a class="anchor" href="#wavespeed">
          <svg class="octicon octicon-link" aria-hidden="true"><path d="x"/></svg>
        </a>
        WaveSpeed
      </h2>
    `

    const adoc = webHtmlToAsciidoc(html)

    expect(adoc).toBe('== WaveSpeed')
    expect(adoc).not.toContain('octicon')
  })

  it('keeps github private image links as image macro', () => {
    const url =
      'https://private-user-images.githubusercontent.com/209755920/568104381.png?jwt=example'
    const html = `
      <p>
        <a class="image" href="${url}">
          <img src="${url}" alt="Playground Screenshot">
        </a>
      </p>
    `

    const adoc = webHtmlToAsciidoc(html)

    expect(adoc).toBe(`image:${url}[Playground Screenshot]`)
  })
})
