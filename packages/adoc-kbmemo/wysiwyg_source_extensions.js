import { diagramWysiwygExtension } from './src/diagram_wysiwyg.js'
import { listContinuationExtension } from './src/list_continuation.js'
import { mathWysiwygExtension } from './src/math_wysiwyg.js'
import { wikiAutocompletion } from './src/wiki_completion.js'
import { viewportLineRangeSyncExtension } from './src/viewport_lazy.js'
import { wikiLinkWysiwygExtension } from './src/wiki_link_wysiwyg.js'

/**
 * KBMemo 向け WYSIWYG ユニット内ソース CodeMirror 拡張。
 *
 * @param {{ getWikiConfig?: () => { completionsUrl?: string, labelsUrl?: string, memoId?: string | null }, getMemoId?: () => string | null | undefined, rawSourceMode?: boolean }} [options]
 */
export function createKbmemoWysiwygSourceExtensions({
  getWikiConfig,
  getMemoId,
  rawSourceMode = true,
} = {}) {
  const extensions = [
    ...viewportLineRangeSyncExtension(),
    listContinuationExtension(),
  ]

  if (!rawSourceMode) {
    extensions.push(
      diagramWysiwygExtension(getMemoId ?? (() => null)),
      ...mathWysiwygExtension(),
    )
  }

  if (!getWikiConfig) return extensions

  const getCompletionsConfig = () => {
    const { completionsUrl, memoId } = getWikiConfig()
    return { url: completionsUrl, memoId: memoId ?? null }
  }
  const getLabelsConfig = () => {
    const { labelsUrl, memoId } = getWikiConfig()
    return { url: labelsUrl, memoId: memoId ?? null }
  }

  extensions.push(...wikiAutocompletion(getCompletionsConfig))

  if (!rawSourceMode) {
    extensions.push(...wikiLinkWysiwygExtension(getLabelsConfig))
  }

  return extensions
}
