/** @type {string[]} */
export const KBMEMO_PACKAGES = [
  '@kbmemo/adoc-codemirror',
  '@kbmemo/adoc-kbmemo',
  '@kbmemo/adoc-preview',
  '@kbmemo/adoc-wysiwyg',
  '@kbmemo/adoc-editor',
]

/** @type {import('tsup').Options['external']} */
export const DEFAULT_EXTERNAL = [
  ...KBMEMO_PACKAGES,
  '@asciidoctor/core',
  /^@codemirror\//,
  /^highlight\.js/,
  /^katex/,
]

/**
 * @param {import('tsup').Options} [overrides]
 * @returns {import('tsup').Options}
 */
export function createPackageTsupConfig(overrides = {}) {
  return {
    entry: ['index.js'],
    format: ['esm'],
    outDir: 'dist',
    sourcemap: true,
    clean: true,
    splitting: false,
    treeshake: true,
    target: 'es2022',
    external: DEFAULT_EXTERNAL,
    ...overrides,
  }
}
