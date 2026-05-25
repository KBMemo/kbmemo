import 'highlight.js/styles/github.min.css'
import '@kbmemo/adoc-preview/preview_hljs.css'
import { createLivePreview as createLivePreviewCore } from '@kbmemo/adoc-preview'
import { initThemeSelect } from '../theme/theme.js'

/** @param {Parameters<typeof createLivePreviewCore>[0]} options */
export function createLivePreview(options) {
  return createLivePreviewCore({
    ...options,
    initPreviewSkinSelect: options.initPreviewSkinSelect ?? initThemeSelect,
  })
}

export {
  asciidocHighlight,
  refreshHighlights,
  refreshPreview,
  clearParseCache,
} from '@kbmemo/adoc-codemirror'
export { createMemoWysiwygEditor } from './wysiwyg_mount.js'
