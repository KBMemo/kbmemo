import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

const rootDir = path.dirname(fileURLToPath(import.meta.url))
const packagesDir = path.resolve(rootDir, '../../packages')

export default defineConfig({
  root: rootDir,
  resolve: {
    alias: [
      {
        find: '@kbmemo/adoc-wysiwyg/wysiwyg.css',
        replacement: path.join(packagesDir, 'adoc-wysiwyg/wysiwyg.css'),
      },
      {
        find: '@kbmemo/adoc-preview/preview_hljs.css',
        replacement: path.join(packagesDir, 'adoc-preview/preview_hljs.css'),
      },
      {
        find: '@kbmemo/adoc-kbmemo',
        replacement: path.join(packagesDir, 'adoc-kbmemo/index.js'),
      },
      {
        find: '@kbmemo/adoc-codemirror',
        replacement: path.join(packagesDir, 'adoc-codemirror/index.js'),
      },
      {
        find: '@kbmemo/adoc-preview',
        replacement: path.join(packagesDir, 'adoc-preview/index.js'),
      },
      {
        find: '@kbmemo/adoc-wysiwyg',
        replacement: path.join(packagesDir, 'adoc-wysiwyg/index.js'),
      },
      {
        find: '@kbmemo/adoc-editor',
        replacement: path.join(packagesDir, 'adoc-editor/index.js'),
      },
    ],
  },
})
