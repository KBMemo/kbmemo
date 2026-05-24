import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const fixtureDir = dirname(fileURLToPath(import.meta.url))

/** @param {string} name */
export function readAsciiDocFixture(name) {
  return readFileSync(join(fixtureDir, `${name}.adoc`), 'utf8')
}

/** @param {string} source */
export function parseSyntaxRefIds(source) {
  const ids = []
  const pattern = /^\/\/ kbmemo:syntax-ref:([a-z0-9-]+)/gm
  for (const match of source.matchAll(pattern)) {
    ids.push(match[1])
  }
  return ids
}

export const SYNTAX_QUICK_REFERENCE = readAsciiDocFixture('syntax-quick-reference')
export const SYNTAX_QUICK_REFERENCE_IDS = parseSyntaxRefIds(SYNTAX_QUICK_REFERENCE)
