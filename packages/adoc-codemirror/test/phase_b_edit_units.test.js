import { describe, expect, it } from 'vitest'
import { parseEditUnitsFromSource } from '../index.js'
import {
  extractSyntaxRefSections,
  SYNTAX_QUICK_REFERENCE,
} from '@kbmemo/test-fixtures'

/** @param {string} body */
function unitsForBody(body) {
  return parseEditUnitsFromSource(`= Title\n\n${body}`).filter((unit) => unit.startLine >= 2)
}

/** @param {string} id */
function sectionBody(id) {
  const section = extractSyntaxRefSections(SYNTAX_QUICK_REFERENCE).find((entry) => entry.id === id)
  if (!section) throw new Error(`missing syntax-ref section: ${id}`)
  return section.body
}

describe('Phase B edit unit boundaries', () => {
  it('keeps description lists in one unit', () => {
    const units = unitsForBody(sectionBody('lists-description'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain('First term::')
    expect(units[0].adoc).toContain('Second term::')
  })

  it('keeps qanda lists in one unit', () => {
    const units = unitsForBody(sectionBody('lists-qanda'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain('[qanda]')
    expect(units[0].adoc).toContain('Are backpacks allowed?::')
  })

  it('keeps checklist lists in one unit', () => {
    const units = unitsForBody(sectionBody('lists-checklist'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain('[*] checked')
  })

  it('keeps delimited admonitions in one unit', () => {
    const units = unitsForBody(sectionBody('admonitions-block'))
    expect(units.some((unit) => unit.adoc.includes('[NOTE]') && unit.adoc.includes('===='))).toBe(true)
    expect(units.filter((unit) => unit.adoc.includes('====')).length).toBe(1)
  })

  it('keeps sidebar title and block together', () => {
    const units = unitsForBody(sectionBody('blocks-sidebar'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain('.Optional Title')
    expect(units[0].adoc).toContain('****')
  })

  it('keeps paragraph-style quotes in one unit', () => {
    const units = unitsForBody(sectionBody('blocks-blockquote'))
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

  it('keeps delimited quotes in one unit', () => {
    const units = unitsForBody(sectionBody('blocks-blockquote'))
    expect(
      units.some(
        (unit) =>
          unit.adoc.includes('[quote,Abraham Lincoln')
          && unit.adoc.includes('____')
      )
    ).toBe(true)
  })

  it('keeps open blocks as separate units', () => {
    const units = unitsForBody(sectionBody('blocks-open'))
    expect(units).toHaveLength(2)
    expect(units[0].adoc.trim()).toMatch(/^--/)
    expect(units[1].adoc).toContain('[source]')
  })

  it('keeps csv tables in one unit each', () => {
    const units = unitsForBody(sectionBody('tables-csv'))
    expect(units).toHaveLength(2)
    expect(units.some((unit) => unit.adoc.startsWith(',==='))).toBe(true)
    expect(units.some((unit) => unit.adoc.includes('[%header,format=csv]'))).toBe(true)
  })

  it('keeps dsv tables in one unit', () => {
    const units = unitsForBody(sectionBody('tables-dsv'))
    expect(units).toHaveLength(1)
    expect(units[0].adoc).toContain(':===')
    expect(units[0].adoc).toContain('Robyn:Indestructible:Dance')
  })
})
