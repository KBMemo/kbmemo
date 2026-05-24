#!/usr/bin/env node
import { execFileSync } from 'node:child_process'

const WORKSPACES = [
  '@kbmemo/adoc-kbmemo',
  '@kbmemo/adoc-codemirror',
  '@kbmemo/adoc-preview',
  '@kbmemo/adoc-wysiwyg',
  '@kbmemo/adoc-editor',
]

const REQUIRED_PATHS = {
  '@kbmemo/adoc-kbmemo': ['dist/index.js'],
  '@kbmemo/adoc-codemirror': ['dist/index.js'],
  '@kbmemo/adoc-preview': ['dist/index.js', 'dist/preview_hljs.css'],
  '@kbmemo/adoc-wysiwyg': ['dist/index.js', 'dist/wysiwyg.css', 'dist/contextMenu.css'],
  '@kbmemo/adoc-editor': ['dist/index.js'],
}

for (const workspace of WORKSPACES) {
  const output = execFileSync(
    'npm',
    ['pack', '--dry-run', '--json', '--ignore-scripts', '--workspace', workspace],
    { encoding: 'utf8' },
  )

  const payload = JSON.parse(output)
  const entry = Array.isArray(payload) ? payload[0] : payload
  const paths = new Set((entry.files ?? []).map((file) => file.path))

  for (const required of REQUIRED_PATHS[workspace]) {
    if (!paths.has(required)) {
      console.error(`${workspace}: missing ${required} in npm pack output`)
      process.exit(1)
    }
  }

  console.log(`${workspace}: pack ok (${entry.filename ?? entry.name})`)
}
