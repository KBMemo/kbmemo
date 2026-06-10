import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'

const rootDir = path.dirname(fileURLToPath(import.meta.url))
const packagesDir = path.resolve(rootDir, 'packages')

/** Workspace 開発時はソースを直接参照（package exports は dist 向け） */
const workspaceAliases = [
  {
    find: '@kbmemo/adoc-wysiwyg/wysiwyg.css',
    replacement: path.join(packagesDir, 'adoc-wysiwyg/wysiwyg.css'),
  },
  {
    find: '@kbmemo/adoc-wysiwyg/contextMenu.css',
    replacement: path.join(packagesDir, 'adoc-wysiwyg/contextMenu.css'),
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
    find: '@kbmemo/adoc-preview/preview_hljs.css',
    replacement: path.join(packagesDir, 'adoc-preview/preview_hljs.css'),
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
]

export default defineConfig({
  resolve: {
    alias: workspaceAliases,
  },
  plugins: [
    RubyPlugin(),
  ],
})
