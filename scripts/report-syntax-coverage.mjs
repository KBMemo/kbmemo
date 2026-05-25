#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Window } from 'happy-dom'
import {
  clearParseCache,
  parseEditUnitsFromSource,
  refreshHighlights,
} from '@kbmemo/adoc-codemirror'
import {
  ROADMAP_PATH,
  SYNTAX_QUICK_REFERENCE,
  SYNTAX_QUICK_REFERENCE_IDS,
  SYNTAX_QUICK_REFERENCE_SECTIONS,
  parseRoadmapSyntaxRefIds,
} from '../test/fixtures/asciidoc/index.js'

const rootDir = join(dirname(fileURLToPath(import.meta.url)), '..')
const outputPath = process.argv.includes('--write')
  ? join(rootDir, 'tmp/syntax-coverage-report.json')
  : null

installDomGlobals()

const roadmapSource = readFileSync(ROADMAP_PATH, 'utf8')
const roadmapIds = parseRoadmapSyntaxRefIds(roadmapSource)
const fixtureIds = new Set(SYNTAX_QUICK_REFERENCE_IDS)
const roadmapIdSet = new Set(roadmapIds)

const missingInRoadmap = SYNTAX_QUICK_REFERENCE_IDS.filter((id) => !roadmapIdSet.has(id))
const missingInFixture = roadmapIds.filter((id) => !fixtureIds.has(id))

if (missingInRoadmap.length > 0 || missingInFixture.length > 0) {
  console.error('Fixture and roadmap ids are out of sync.')
  if (missingInRoadmap.length > 0) {
    console.error(`  missing in roadmap: ${missingInRoadmap.join(', ')}`)
  }
  if (missingInFixture.length > 0) {
    console.error(`  missing in fixture: ${missingInFixture.join(', ')}`)
  }
  process.exit(1)
}

clearParseCache()
const wholeDocument = measureDocument('__whole__', SYNTAX_QUICK_REFERENCE)
const sections = SYNTAX_QUICK_REFERENCE_SECTIONS.map(({ id, adoc }) => measureDocument(id, adoc))

const report = {
  generatedAt: new Date().toISOString(),
  fixtureIds: SYNTAX_QUICK_REFERENCE_IDS.length,
  roadmapIds: roadmapIds.length,
  wholeDocument,
  sections,
}

if (outputPath) {
  writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`)
  console.log(`Wrote ${outputPath}`)
}

printSummary(report)
process.exit(0)

function installDomGlobals() {
  const window = new Window({ url: 'https://localhost/' })
  globalThis.window = window
  globalThis.document = window.document
  globalThis.DOMParser = window.DOMParser
  globalThis.Node = window.Node
}

/** @param {string} id @param {string} source */
function measureDocument(id, source) {
  clearParseCache()
  let hlOk = true
  let euOk = true
  /** @type {string | null} */
  let hlError = null
  /** @type {string | null} */
  let euError = null
  let highlightSpans = 0
  let editUnits = 0

  try {
    highlightSpans = refreshHighlights(source).length
  } catch (error) {
    hlOk = false
    hlError = error instanceof Error ? error.message : String(error)
  }

  try {
    editUnits = parseEditUnitsFromSource(source).length
  } catch (error) {
    euOk = false
    euError = error instanceof Error ? error.message : String(error)
  }

  return {
    id,
    hlOk,
    euOk,
    highlightSpans,
    editUnits,
    hlError,
    euError,
  }
}

/** @param {ReturnType<typeof measureDocument>[]} sections */
function countFailures(sections) {
  return sections.filter((section) => !section.hlOk || !section.euOk).length
}

/** @param {{ fixtureIds: number, wholeDocument: ReturnType<typeof measureDocument>, sections: ReturnType<typeof measureDocument>[] }} report */
function printSummary(report) {
  const sectionFailures = countFailures(report.sections)
  const wholeFailures = Number(!report.wholeDocument.hlOk || !report.wholeDocument.euOk)

  console.log(`Syntax coverage report (${report.fixtureIds} syntax-ref ids)`)
  console.log(`  whole document: HL=${report.wholeDocument.highlightSpans} spans, EU=${report.wholeDocument.editUnits} units`)
  console.log(`  per-section smoke: ${report.sections.length} sections, ${sectionFailures} failures`)
  console.log(`  fixture ↔ roadmap sync: ok (${report.fixtureIds} ids)`)

  if (wholeFailures > 0 || sectionFailures > 0) {
    for (const section of [report.wholeDocument, ...report.sections]) {
      if (section.hlOk && section.euOk) continue
      console.error(`  ${section.id}: HL=${section.hlOk ? 'ok' : section.hlError}, EU=${section.euOk ? 'ok' : section.euError}`)
    }
    process.exit(1)
  }
}
