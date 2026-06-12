function createWikiLinkHighlight({ Decoration, MatchDecorator, ViewPlugin }) {
  const wikiLinkMatcher = new MatchDecorator({
    regexp: /\[\[[^\]|]+?(?:\|[^\]]+?)?\]\]/g,
    decoration: Decoration.mark({ class: 'cm-memo-wiki-link' }),
  })

  return ViewPlugin.fromClass(
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
}

/**
 * WYSIWYG ユニット内ソース CodeMirror 向け拡張（Wiki リンク装飾 + ホスト注入拡張）。
 *
 * @param {{ sourceExtensions?: import('@codemirror/state').Extension[], getWikiConfig?: () => unknown, codeMirrorView?: { Decoration: object, MatchDecorator: object, ViewPlugin: object } }} [options]
 */
export function createWysiwygSourceExtensions({ sourceExtensions = [], getWikiConfig, codeMirrorView } = {}) {
  const extensions = [...sourceExtensions]

  if (getWikiConfig) {
    extensions.push(createWikiLinkHighlight(codeMirrorView))
  }

  return extensions
}
