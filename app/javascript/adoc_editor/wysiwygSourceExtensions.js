import { Decoration, MatchDecorator, ViewPlugin } from '@codemirror/view'
import { mathWysiwygExtension } from '../memo_body_editor/math_wysiwyg.js'
import { wikiAutocompletion } from '../memo_body_editor/wiki_completion.js'
import { viewportLineRangeSyncExtension } from '../memo_body_editor/viewport_lazy.js'
import { wikiLinkWysiwygExtension } from '../memo_body_editor/wiki_link_wysiwyg.js'

const wikiLinkMatcher = new MatchDecorator({
  regexp: /\[\[[^\]|]+?(?:\|[^\]]+?)?\]\]/g,
  decoration: Decoration.mark({ class: 'cm-memo-wiki-link' }),
})

const wikiLinkHighlight = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = wikiLinkMatcher.createDeco(view)
    }

    update(update) {
      this.decorations = wikiLinkMatcher.updateDeco(update, this.decorations)
    }
  },
  { decorations: (v) => v.decorations },
)

/**
 * WYSIWYG ユニット内ソース CodeMirror 向け拡張（Wiki リンク + 数式 KaTeX プレビュー）。
 *
 * @param {() => { completionsUrl?: string, labelsUrl?: string, memoId?: string | null } | undefined} getWikiConfig
 */
export function createWysiwygSourceExtensions(getWikiConfig) {
  const extensions = [...viewportLineRangeSyncExtension(), ...mathWysiwygExtension()]

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
    wikiLinkHighlight,
    ...wikiAutocompletion(getCompletionsConfig),
    ...wikiLinkWysiwygExtension(getLabelsConfig),
  )

  return extensions
}
