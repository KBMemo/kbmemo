/** Shared workspace list and publish order for @kbmemo/adoc-* packages. */

export const KBMEMO_PACKAGE_VERSION = '0.1.0'

/** @type {readonly string[]} */
export const KBMEMO_WORKSPACES = [
  '@kbmemo/adoc-kbmemo',
  '@kbmemo/adoc-codemirror',
  '@kbmemo/adoc-preview',
  '@kbmemo/adoc-wysiwyg',
  '@kbmemo/adoc-editor',
]

/** Dependency order for registry publish (deps first). */
export const KBMEMO_PUBLISH_ORDER = [...KBMEMO_WORKSPACES]

export const KBMEMO_REPOSITORY = {
  type: 'git',
  url: 'https://gitea.artif.org/Artif.org/kbmemo_site.git',
}
