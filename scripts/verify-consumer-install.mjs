#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import {
  KBMEMO_PACKAGE_VERSION,
  KBMEMO_WORKSPACES,
} from './package-workspaces.mjs'

const rootDir = join(dirname(fileURLToPath(import.meta.url)), '..')

const PEER_DEPENDENCIES = {
  '@asciidoctor/core': '^4.0.4',
  '@codemirror/state': '^6.6.0',
  '@codemirror/view': '^6.43.0',
  'highlight.js': '^11.11.1',
}

execFileSync('npm', ['run', 'build:packages'], { cwd: rootDir, stdio: 'inherit' })

const workDir = mkdtempSync(join(tmpdir(), 'kbmemo-adoc-consumer-'))
const packDir = join(workDir, 'packs')
mkdirSync(packDir)

/** @type {Record<string, string>} */
const packed = {}

for (const workspace of KBMEMO_WORKSPACES) {
  const output = execFileSync(
    'npm',
    ['pack', '--json', '--pack-destination', packDir, '--ignore-scripts', '--workspace', workspace],
    { cwd: rootDir, encoding: 'utf8' },
  )
  const entry = JSON.parse(output)[0]
  packed[workspace] = `file:${join(packDir, entry.filename)}`
  console.log(`${workspace}: packed ${entry.filename}`)
}

writeFileSync(
  join(workDir, 'package.json'),
  `${JSON.stringify(
    {
      name: 'adoc-consumer-smoke',
      private: true,
      type: 'module',
      dependencies: {
        ...packed,
        ...PEER_DEPENDENCIES,
      },
    },
    null,
    2,
  )}\n`,
)

writeFileSync(
  join(workDir, 'smoke.mjs'),
  `import {
  createAsciidocHighlight,
  refreshHighlights,
  configureVanillaHost,
  parseEditUnitsFromSource,
} from '@kbmemo/adoc-editor'
import { Decoration, EditorView } from '@codemirror/view'

configureVanillaHost({ memoBase: '/memos' })

const asciidocHighlight = createAsciidocHighlight({ Decoration, EditorView })
if (!Array.isArray(asciidocHighlight)) {
  throw new Error('createAsciidocHighlight returned no extensions')
}

const source = '= Hello\\n\\n* list item'
const spans = await refreshHighlights(source)
if (spans.length === 0) {
  throw new Error('refreshHighlights returned no spans')
}

const units = await parseEditUnitsFromSource(source)
if (units.length === 0) {
  throw new Error('parseEditUnitsFromSource returned no units')
}

console.log('consumer install smoke ok')
`,
)

execFileSync('npm', ['install'], { cwd: workDir, stdio: 'inherit' })
execFileSync('node', ['smoke.mjs'], { cwd: workDir, stdio: 'inherit' })

rmSync(workDir, { recursive: true, force: true })
