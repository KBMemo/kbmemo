// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { highlightPreviewCode } from '../src/codeHighlight.js'

describe('highlightPreviewCode', () => {
  it('highlights source blocks that include callout markers', () => {
    const container = document.createElement('div')
    container.innerHTML = `
      <div class="listingblock">
        <div class="content">
          <pre class="highlightjs highlight">
            <code class="language-ruby hljs" data-lang="ruby">require 'sinatra' <i class="conum" data-value="1"></i><b>(1)</b>
get '/hi' do <i class="conum" data-value="2"></i><b>(2)</b>
  "Hello World!" <i class="conum" data-value="3"></i><b>(3)</b>
end</code>
          </pre>
        </div>
      </div>
    `

    highlightPreviewCode(container)

    const code = container.querySelector('code')
    expect(code?.querySelectorAll('.conum').length).toBe(3)
    expect(code?.innerHTML).toContain('class="conum"')
    expect(code?.querySelector('[class*="hljs-"]')).not.toBeNull()
  })

  it('highlights plain listing blocks without existing syntax spans', () => {
    const container = document.createElement('div')
    container.innerHTML = `
      <pre><code class="language-ruby" data-lang="ruby">puts 1</code></pre>
    `

    highlightPreviewCode(container)

    expect(container.querySelector('[class*="hljs-"]')).not.toBeNull()
  })

  it('does not re-highlight blocks that are already highlighted', () => {
    const container = document.createElement('div')
    container.innerHTML = `
      <pre><code class="language-ruby hljs" data-lang="ruby"><span class="hljs-keyword">puts</span> 1</code></pre>
    `
    const before = container.querySelector('code')?.innerHTML

    highlightPreviewCode(container)

    expect(container.querySelector('code')?.innerHTML).toBe(before)
  })
})
