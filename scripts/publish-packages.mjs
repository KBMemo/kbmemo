#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  KBMEMO_PUBLISH_ORDER,
  KBMEMO_PACKAGE_VERSION,
} from './package-workspaces.mjs'

const rootDir = join(dirname(fileURLToPath(import.meta.url)), '..')
const dryRun = process.argv.includes('--dry-run')
const registry = process.env.NPM_PUBLISH_REGISTRY

if (!dryRun && !registry) {
  console.error('Set NPM_PUBLISH_REGISTRY before publishing (or pass --dry-run).')
  console.error('Example: NPM_PUBLISH_REGISTRY=https://gitea.artif.org/api/packages/Artif.org/npm/')
  console.error('Copy .npmrc.example, set NPM_TOKEN, and run npm run verify:publish first.')
  process.exit(1)
}

execFileSync('npm', ['run', 'verify:publish'], { cwd: rootDir, stdio: 'inherit' })
execFileSync('npm', ['run', 'build:packages'], { cwd: rootDir, stdio: 'inherit' })

for (const workspace of KBMEMO_PUBLISH_ORDER) {
  const pkgPath = join(rootDir, 'packages', workspace.replace('@kbmemo/', ''), 'package.json')
  const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'))

  if (pkg.private) {
    console.error(`${workspace}: cannot publish while "private": true`)
    process.exit(1)
  }

  if (pkg.version !== KBMEMO_PACKAGE_VERSION) {
    console.error(`${workspace}: expected version ${KBMEMO_PACKAGE_VERSION}`)
    process.exit(1)
  }

  const args = ['publish', '--workspace', workspace]
  if (dryRun) {
    args.push('--dry-run')
  } else {
    args.push('--registry', registry)
  }

  console.log(`> npm ${args.join(' ')}`)
  execFileSync('npm', args, { cwd: rootDir, stdio: 'inherit' })
}

console.log(dryRun ? 'Dry-run publish completed.' : `Published ${KBMEMO_PUBLISH_ORDER.length} packages at ${KBMEMO_PACKAGE_VERSION}.`)
