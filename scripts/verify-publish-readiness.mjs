#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  KBMEMO_PACKAGE_VERSION,
  KBMEMO_WORKSPACES,
} from './package-workspaces.mjs'

const rootDir = join(dirname(fileURLToPath(import.meta.url)), '..')
const packagesDir = join(rootDir, 'packages')

/** @param {string} workspace */
function packageDir(workspace) {
  return join(packagesDir, workspace.replace('@kbmemo/', ''))
}

/** @param {string} workspace */
function readPackageJson(workspace) {
  const path = join(packageDir(workspace), 'package.json')
  return { path, json: JSON.parse(readFileSync(path, 'utf8')) }
}

let failed = false

for (const workspace of KBMEMO_WORKSPACES) {
  const { path, json } = readPackageJson(workspace)

  if (json.private) {
    console.error(`${workspace}: "private": true must be removed before registry publish`)
    failed = true
  }

  if (json.version !== KBMEMO_PACKAGE_VERSION) {
    console.error(`${workspace}: version must be ${KBMEMO_PACKAGE_VERSION} (got ${json.version})`)
    failed = true
  }

  if (!json.description?.trim()) {
    console.error(`${workspace}: missing description`)
    failed = true
  }

  if (!json.repository?.url) {
    console.error(`${workspace}: missing repository.url`)
    failed = true
  }

  for (const [name, version] of Object.entries(json.dependencies ?? {})) {
    if (!name.startsWith('@kbmemo/')) continue
    if (version !== KBMEMO_PACKAGE_VERSION) {
      console.error(`${workspace}: dependency ${name} must be ${KBMEMO_PACKAGE_VERSION} (got ${version})`)
      failed = true
    }
  }

  console.log(`${workspace}: publish metadata ok (${path})`)
}

if (failed) {
  process.exit(1)
}

console.log(`All ${KBMEMO_WORKSPACES.length} packages are publish-ready at ${KBMEMO_PACKAGE_VERSION}.`)
