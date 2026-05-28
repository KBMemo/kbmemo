// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { highlightPreviewCode } from '../src/codeHighlight.js'

describe('highlightPreviewCode', () => {
  it('preserves source callout markers already rendered by Asciidoctor', () => {
    const container = document.createElement('div')
    container.innerHTML = `
      <div class="listingblock">
        <div class="content">
          <pre class="highlightjs highlight">
            <code class="language-ruby hljs" data-lang="ruby">
              require 'sinatra' <i class="conum" data-value="1"></i><b>(1)</b>
            </code>
          </pre>
        </div>
      </div>
    `

    highlightPreviewCode(container)

    expect(container.querySelector('.conum')).not.toBeNull()
    expect(container.querySelector('code')?.innerHTML).toContain('class="conum"')
  })

  it('highlights plain listing blocks without existing syntax spans', () => {
    const container = document.createElement('div')
    container.innerHTML = `
      <pre><code class="language-ruby" data-lang="ruby">puts 1</code></pre>
    `

    highlightPreviewCode(container)

    expect(container.querySelector('[class*="hljs-"]')).not.toBeNull()
  })
})
