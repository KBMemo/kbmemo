import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'

const rootDir = path.dirname(fileURLToPath(import.meta.url))
const packagesDir = path.resolve(rootDir, 'packages')

export default defineConfig({
  resolve: {
    alias: {
      '@kbmemo/adoc-kbmemo': path.join(packagesDir, 'adoc-kbmemo/index.js'),
      '@kbmemo/adoc-codemirror': path.join(packagesDir, 'adoc-codemirror/index.js'),
      '@kbmemo/adoc-preview': path.join(packagesDir, 'adoc-preview/index.js'),
      '@kbmemo/adoc-wysiwyg': path.join(packagesDir, 'adoc-wysiwyg/index.js'),
      '@kbmemo/adoc-editor': path.join(packagesDir, 'adoc-editor/index.js'),
      '@kbmemo/test-fixtures': path.join(rootDir, 'test/fixtures/asciidoc/index.js'),
    },
  },
  test: {
    include: ['packages/**/test/**/*.test.js'],
  },
})
