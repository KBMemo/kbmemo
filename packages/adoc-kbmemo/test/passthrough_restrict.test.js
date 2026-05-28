import { describe, expect, it } from 'vitest'
import { restrictPassthroughInSource } from '../src/passthrough_restrict.js'

describe('restrictPassthroughInSource', () => {
  it('converts block passthrough delimiters to literal blocks', () => {
    const source = `++++
<script>alert(1)</script>
++++`

    expect(restrictPassthroughInSource(source)).toBe(`....
<script>alert(1)</script>
....`)
  })

  it('closes unterminated block passthrough as literal', () => {
    const source = `++++
<script>alert(1)</script>`

    expect(restrictPassthroughInSource(source)).toBe(`....
<script>alert(1)</script>
....`)
  })

  it('escapes inline pass macro passthrough', () => {
    const source = 'pass:[<script>alert(1)</script>]'

    expect(restrictPassthroughInSource(source)).toBe('\\pass:[<script>alert(1)</script>]')
  })

  it('escapes inline triple-plus passthrough', () => {
    const source = '+++<del>removed</del>+++'

    expect(restrictPassthroughInSource(source)).toBe('\\+++<del>removed</del>+++')
  })

  it('does not double-escape already escaped inline passthrough', () => {
    const source = '\\pass:[safe]'

    expect(restrictPassthroughInSource(source)).toBe('\\pass:[safe]')
  })
})
