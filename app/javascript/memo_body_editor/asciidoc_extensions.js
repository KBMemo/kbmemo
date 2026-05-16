import { StreamLanguage, syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language"
import { asciidoc } from "codemirror-asciidoc"
import { Decoration, MatchDecorator, ViewPlugin } from "@codemirror/view"

const wikiLinkMatcher = new MatchDecorator({
  regexp: /\[\[[^\]|]+?(?:\|[^\]]+?)?\]\]/g,
  decoration: Decoration.mark({ class: "cm-memo-wiki-link" })
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
  { decorations: (v) => v.decorations }
)

export function asciidocExtensions() {
  return [
    StreamLanguage.define(asciidoc),
    syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
    wikiLinkHighlight
  ]
}
