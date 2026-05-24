import { describe, expect, it } from 'vitest'
import { scanCodeBlocks } from '../index.js'
import { mockDoc } from './helpers.js'

describe('scanCodeBlocks', () => {
  it('finds AsciiDoc listing blocks', () => {
    const doc = mockDoc(
      `[source,ruby]
.Ruby sample
----
puts "hi"
----`,
    )

    const blocks = scanCodeBlocks(doc)
    expect(blocks).toHaveLength(1)
    expect(blocks[0].kind).toBe('source')
    expect(blocks[0].language).toBe('ruby')
    expect(blocks[0].title).toBe('Ruby sample')
  })

  it('finds fenced code blocks', () => {
    const doc = mockDoc(
      `\`\`\`js
console.log("ok")
\`\`\``,
    )

    const blocks = scanCodeBlocks(doc)
    expect(blocks).toHaveLength(1)
    expect(blocks[0].kind).toBe('fence')
    expect(blocks[0].language).toBe('js')
  })
})
