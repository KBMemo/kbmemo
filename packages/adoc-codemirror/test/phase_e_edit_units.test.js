import { describe, expect, it } from 'vitest'
import { parseEditUnitsFromSource } from '../index.js'
import {
  extractSyntaxRefSections,
  SYNTAX_QUICK_REFERENCE,
} from '@kbmemo/test-fixtures'

/** @param {string} body */
async function unitsForBody(body) {
  return (await parseEditUnitsFromSource(`= Title\n\n${body}`)).filter((unit) => unit.startLine >= 2)
}

/** @param {string} id */
function sectionBody(id) {
  const section = extractSyntaxRefSections(SYNTAX_QUICK_REFERENCE).find((entry) => entry.id === id)
  if (!section) throw new Error(`missing syntax-ref section: ${id}`)
  return section.body
}

describe('Phase E edit unit boundaries', () => {
  it('keeps passthrough blocks in one unit', async () => {
    const units = await unitsForBody(sectionBody('blocks-passthrough'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain('++++')
    expect(units[0].adoc).toContain('<p>')
  })

  it('keeps formatted tables in one unit', async () => {
    const units = (await unitsForBody(sectionBody('tables-formatted'))).filter(
      (unit) => !unit.adoc.trim().startsWith('//')
    )
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain('|===')
    expect(units[0].adoc).toContain('2.2+')
  })

  it('splits include lines into separate units', async () => {
    const units = (await unitsForBody(sectionBody('includes'))).filter(
      (unit) => !unit.adoc.trim().startsWith('//')
    )
    expect(units.length).toBeGreaterThanOrEqual(2)
    expect(units.some((unit) => unit.adoc.includes('include::basics.adoc[]'))).toBe(true)
    expect(units.some((unit) => unit.adoc.includes('include::installation.adoc[]'))).toBe(true)
  })
})
