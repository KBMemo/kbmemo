import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import tailwindcss from '@tailwindcss/vite'
import RubyPlugin from 'vite-plugin-ruby'

const rootDir = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  resolve: {
    alias: {
      '@kbmemo/adoc-kbmemo': path.resolve(rootDir, 'packages/adoc-kbmemo'),
      '@kbmemo/adoc-editor-internal': path.resolve(rootDir, 'app/javascript/adoc_editor'),
    },
  },
  plugins: [
    RubyPlugin(),
    tailwindcss(),
  ],
})
