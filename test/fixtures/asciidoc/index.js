import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const fixtureDir = dirname(fileURLToPath(import.meta.url))
const repoRoot = join(fixtureDir, '..', '..', '..')

export const ROADMAP_PATH = join(repoRoot, 'docs/architecture/asciidoc-syntax-coverage-roadmap.adoc')

/** Minimal document header for per-section HL/EU smoke tests. */
export const SYNTAX_REF_DOCUMENT_HEADER = `= Syntax ref smoke
:experimental:
:source-highlighter: highlightjs
:stem: latexmath

`

const SYNTAX_REF_MARKER = /^\/\/ kbmemo:syntax-ref:([a-z0-9-]+)/gm
const ROADMAP_ID_PATTERN = /^\|([a-z0-9-]+) \|/gm

/** @param {string} name */
export function readAsciiDocFixture(name) {
  return readFileSync(join(fixtureDir, `${name}.adoc`), 'utf8')
}

/** @param {string} source */
export function parseSyntaxRefIds(source) {
  const ids = []
  for (const match of source.matchAll(SYNTAX_REF_MARKER)) {
    ids.push(match[1])
  }
  return ids
}

/**
 * @param {string} body Section body without document header.
 * @returns {string}
 */
export function wrapSyntaxRefSection(body) {
  const trimmed = body.trim()
  if (!trimmed) return SYNTAX_REF_DOCUMENT_HEADER.trimEnd()
  return `${SYNTAX_REF_DOCUMENT_HEADER}${trimmed}\n`
}

/**
 * Split a fixture into syntax-ref sections for per-id smoke tests.
 *
 * @param {string} source
 * @returns {{ id: string, body: string, adoc: string }[]}
 */
export function extractSyntaxRefSections(source) {
  const matches = [...source.matchAll(SYNTAX_REF_MARKER)]
  /** @type {{ id: string, body: string, adoc: string }[]} */
  const sections = []

  for (let index = 0; index < matches.length; index++) {
    const match = matches[index]
    const id = match[1]
    const bodyStart = match.index + match[0].length
    const bodyEnd = index + 1 < matches.length ? matches[index + 1].index : source.length
    const body = source.slice(bodyStart, bodyEnd).replace(/^\n/, '').replace(/\n$/, '')
    sections.push({ id, body, adoc: wrapSyntaxRefSection(body) })
  }

  return sections
}

/**
 * Parse syntax-ref ids from the coverage table in the roadmap AsciiDoc.
 *
 * @param {string} roadmapSource
 * @returns {string[]}
 */
export function parseRoadmapSyntaxRefIds(roadmapSource) {
  const ids = []
  for (const match of roadmapSource.matchAll(ROADMAP_ID_PATTERN)) {
    const id = match[1]
    if (id === 'syntax-ref') continue
    ids.push(id)
  }
  return ids
}

export const SYNTAX_QUICK_REFERENCE = readAsciiDocFixture('syntax-quick-reference')
export const SYNTAX_QUICK_REFERENCE_IDS = parseSyntaxRefIds(SYNTAX_QUICK_REFERENCE)
export const SYNTAX_QUICK_REFERENCE_SECTIONS = extractSyntaxRefSections(SYNTAX_QUICK_REFERENCE)
