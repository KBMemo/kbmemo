import { diagramWysiwygExtension } from './src/diagram_wysiwyg.js'
import { mathWysiwygExtension } from './src/math_wysiwyg.js'
import { wikiAutocompletion } from './src/wiki_completion.js'
import { viewportLineRangeSyncExtension } from './src/viewport_lazy.js'
import { wikiLinkWysiwygExtension } from './src/wiki_link_wysiwyg.js'

/**
 * KBMemo 向け WYSIWYG ユニット内ソース CodeMirror 拡張。
 *
 * @param {{ getWikiConfig?: () => { completionsUrl?: string, labelsUrl?: string, memoId?: string | null }, getMemoId?: () => string | null | undefined }} [options]
 */
export function createKbmemoWysiwygSourceExtensions({ getWikiConfig, getMemoId } = {}) {
  const extensions = [
    ...viewportLineRangeSyncExtension(),
    diagramWysiwygExtension(getMemoId ?? (() => null)),
    ...mathWysiwygExtension(),
  ]

  if (!getWikiConfig) return extensions

  const getCompletionsConfig = () => {
    const { completionsUrl, memoId } = getWikiConfig()
    return { url: completionsUrl, memoId: memoId ?? null }
  }
  const getLabelsConfig = () => {
    const { labelsUrl, memoId } = getWikiConfig()
    return { url: labelsUrl, memoId: memoId ?? null }
  }

  extensions.push(
    ...wikiAutocompletion(getCompletionsConfig),
    ...wikiLinkWysiwygExtension(getLabelsConfig),
  )

  return extensions
}
