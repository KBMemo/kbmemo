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

/** Asciidoctor AST ハイライト + KBMemo 固有の wiki リンク装飾（初回 connect 時に別チャンク読み込み） */
export async function loadAsciidocExtensions({ EditorView }) {
  const { createAsciidocHighlight } = await import('../../../packages/adoc-codemirror/src/codemirror.js')
  const asciidocHighlight = createAsciidocHighlight({ Decoration, EditorView })
  return [...asciidocHighlight, wikiLinkHighlight]
}
