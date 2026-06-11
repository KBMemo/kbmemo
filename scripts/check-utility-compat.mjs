import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const rootDir = path.resolve(__dirname, '..')
const cssPath = path.join(rootDir, 'app/frontend/styles/utility-compat.css')

const BASELINE = {
  nonEmptyLines: 244,
  rules: 242,
}

const css = fs.readFileSync(cssPath, 'utf8')
const withoutComments = css.replace(/\/\*[\s\S]*?\*\//g, '')
const nonEmptyLines = withoutComments
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter(Boolean).length
const selectors = [...withoutComments.matchAll(/([^{}@][^{}]*)\{/g)]
  .map((match) => match[1].trim())
  .filter((selector) => selector && !selector.startsWith('media'))

const duplicateSelectors = selectors.filter(
  (selector, index) => selectors.indexOf(selector) !== index
)
const failures = []

if (nonEmptyLines > BASELINE.nonEmptyLines) {
  failures.push(
    `non-empty lines ${nonEmptyLines} exceed baseline ${BASELINE.nonEmptyLines}`
  )
}

if (selectors.length > BASELINE.rules) {
  failures.push(`rules ${selectors.length} exceed baseline ${BASELINE.rules}`)
}

if (duplicateSelectors.length > 0) {
  failures.push(`duplicate selectors: ${[...new Set(duplicateSelectors)].join(', ')}`)
}

if (failures.length > 0) {
  console.error('utility-compat.css is shrink-only. Move new styling to semantic classes.')
  for (const failure of failures) {
    console.error(`- ${failure}`)
  }
  process.exit(1)
}

console.log(
  `utility-compat.css within baseline: ${nonEmptyLines}/${BASELINE.nonEmptyLines} non-empty lines, ${selectors.length}/${BASELINE.rules} rules`
)
