#!/usr/bin/env node
import { execFileSync } from 'node:child_process'

const WORKSPACES = [
  '@kbmemo/adoc-kbmemo',
  '@kbmemo/adoc-codemirror',
  '@kbmemo/adoc-preview',
  '@kbmemo/adoc-wysiwyg',
  '@kbmemo/adoc-editor',
]

const dryRun = process.argv.includes('--dry-run')
const registry = process.env.NPM_PUBLISH_REGISTRY

if (!dryRun && !registry) {
  console.error('Set NPM_PUBLISH_REGISTRY before publishing (or pass --dry-run).')
  console.error('Example: NPM_PUBLISH_REGISTRY=https://gitea.example/api/packages/ORG/npm/')
  console.error('Also copy .npmrc.example and set NPM_TOKEN. Remove "private": true from package.json when publishing.')
  process.exit(1)
}

for (const workspace of WORKSPACES) {
  const args = ['publish', '--workspace', workspace]
  if (dryRun) {
    args.push('--dry-run')
  } else {
    args.push('--registry', registry)
  }

  console.log(`> npm ${args.join(' ')}`)
  execFileSync('npm', args, { stdio: 'inherit' })
}

console.log(dryRun ? 'Dry-run publish completed.' : 'Publish completed.')
