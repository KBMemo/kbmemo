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

describe('Phase B edit unit boundaries', () => {
  it('keeps description lists in one unit', async () => {
    const units = await unitsForBody(sectionBody('lists-description'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain('First term::')
    expect(units[0].adoc).toContain('Second term::')
  })

  it('keeps qanda lists in one unit', async () => {
    const units = await unitsForBody(sectionBody('lists-qanda'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain('[qanda]')
    expect(units[0].adoc).toContain('Are backpacks allowed?::')
  })

  it('keeps checklist lists in one unit', async () => {
    const units = await unitsForBody(sectionBody('lists-checklist'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain('[*] checked')
  })

  it('keeps delimited admonitions in one unit', async () => {
    const units = await unitsForBody(sectionBody('admonitions-block'))
    expect(units.some((unit) => unit.adoc.includes('[NOTE]') && unit.adoc.includes('===='))).toBe(true)
    expect(units.filter((unit) => unit.adoc.includes('====')).length).toBe(1)
  })

  it('keeps sidebar title and block together', async () => {
    const units = await unitsForBody(sectionBody('blocks-sidebar'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain('.Optional Title')
    expect(units[0].adoc).toContain('****')
  })

  it('keeps paragraph-style quotes in one unit', async () => {
    const units = await unitsForBody(sectionBody('blocks-blockquote'))
    expect(units.some((unit) => unit.adoc.includes('[quote,Albert Einstein]'))).toBe(true)
    expect(
      units.some(
        (unit) =>
          unit.adoc.includes('[quote,Albert Einstein]')
          && unit.adoc.includes('never made a mistake')
          && !unit.adoc.includes('____')
      )
    ).toBe(true)
  })

  it('keeps delimited quotes in one unit', async () => {
    const units = await unitsForBody(sectionBody('blocks-blockquote'))
    expect(
      units.some(
        (unit) =>
          unit.adoc.includes('[quote,Abraham Lincoln')
          && unit.adoc.includes('____')
      )
    ).toBe(true)
  })

  it('keeps paragraph-style quote with -- attribution in one unit', async () => {
    const body = `"paragraph
said"
-- author`
    const units = await unitsForBody(body)
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toBe(body)
  })

  it('keeps delimited quote with -- attribution in one unit', async () => {
    const body = `____
Four score
____
-- Abraham Lincoln`
    const units = await unitsForBody(body)
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toBe(body)
  })

  it('keeps open blocks as separate units', async () => {
    const units = await unitsForBody(sectionBody('blocks-open'))
    expect(units).toHaveLength(2)
    expect(units[0].adoc.trim()).toMatch(/^--/)
    expect(units[1].adoc).toContain('[source]')
  })

  it('keeps csv tables in one unit each', async () => {
    const units = await unitsForBody(sectionBody('tables-csv'))
    expect(units).toHaveLength(2)
    expect(units.some((unit) => unit.adoc.startsWith(',==='))).toBe(true)
    expect(units.some((unit) => unit.adoc.includes('[%header,format=csv]'))).toBe(true)
  })

  it('keeps dsv tables in one unit', async () => {
    const units = await unitsForBody(sectionBody('tables-dsv'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain(':===')
    expect(units[0].adoc).toContain('Robyn:Indestructible:Dance')
  })

  it('preserves leading space on indent literal paragraphs', async () => {
    const units = await unitsForBody(sectionBody('paragraphs-literal'))
    const literalUnit = units.find((unit) => unit.adoc.includes('literal paragraph.'))
    expect(literalUnit).toBeDefined()
    expect(literalUnit.adoc.startsWith(' A literal paragraph.')).toBe(true)
    expect(literalUnit.adoc).toContain('\n One or more consecutive lines')
  })

  it('preserves single-space indent literal lines from syntax fixture', async () => {
    const units = await unitsForBody(sectionBody('literals-paragraph'))
    const literalUnit = units.find((unit) => unit.adoc.includes('literal line'))
    expect(literalUnit).toBeDefined()
    expect(literalUnit.adoc.startsWith(' Indent line')).toBe(true)
  })
})
