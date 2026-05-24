import { Decoration, MatchDecorator, ViewPlugin } from '@codemirror/view'

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
 * WYSIWYG ユニット内ソース CodeMirror 向け拡張（Wiki リンク装飾 + ホスト注入拡張）。
 *
 * @param {{ sourceExtensions?: import('@codemirror/state').Extension[], getWikiConfig?: () => unknown }} [options]
 */
export function createWysiwygSourceExtensions({ sourceExtensions = [], getWikiConfig } = {}) {
  const extensions = [...sourceExtensions]

  if (getWikiConfig) {
    extensions.push(wikiLinkHighlight)
  }

  return extensions
}
