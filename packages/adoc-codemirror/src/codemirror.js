import { EditorView, ViewPlugin, Decoration } from '@codemirror/view'
import { RangeSetBuilder, StateField } from '@codemirror/state'
import { refreshHighlights } from './parseSession.js'

/** @typedef {{ from: number, to: number, className: string }} HighlightSpan */

/** @typedef {{ source: string, spans: HighlightSpan[] }} HighlightState */

export const highlightStateField = StateField.define({
  create(state) {
    const source = state.doc.toString()
    return { source, spans: refreshHighlights(source) }
  },
  update(value, tr) {
    if (tr.docChanged) {
      const source = tr.newDoc.toString()
      return { source, spans: refreshHighlights(source) }
    }
    return value
  },
})

/**
 * @param {HighlightSpan[]} spans
 * @param {number} docLength
 */
function buildDecorations(spans, docLength) {
  if (spans.length === 0) {
    return Decoration.none
  }

  const builder = new RangeSetBuilder()

  for (const span of spans) {
    if (span.from >= docLength) continue
    builder.add(
      span.from,
      Math.min(span.to, docLength),
      Decoration.mark({ class: span.className }),
    )
  }

  return builder.finish()
}

const asciidocHighlighter = ViewPlugin.fromClass(
  class {
    decorations

    constructor(view) {
      this.decorations = this.build(view)
    }

    update(update) {
      if (
        update.docChanged
        || update.viewportChanged
        || update.state.field(highlightStateField) !== update.startState.field(highlightStateField)
      ) {
        this.decorations = this.build(update.view)
      }
    }

    build(view) {
      const { spans } = view.state.field(highlightStateField)
      return buildDecorations(spans, view.state.doc.length)
    }
  },
  {
    decorations: (plugin) => plugin.decorations,
  },
)

export const asciidocHighlight = [
  highlightStateField,
  asciidocHighlighter,
  EditorView.baseTheme({
    '.adoc-heading': { fontWeight: 'bold', color: '#0550ae' },
    '.adoc-h0': { fontSize: '1.05em' },
    '.adoc-h1': { color: '#0969da' },
    '.adoc-h2': { color: '#0550ae' },
    '.adoc-h3': { color: '#033d8b' },
    '.adoc-heading-marker': { color: '#656d76' },
    '.adoc-comment': { color: '#6e7781', fontStyle: 'italic' },
    '.adoc-attribute': { color: '#6639ba' },
    '.adoc-block-attribute': { color: '#8250df' },
    '.adoc-admonition-label': { color: '#bc4c00', fontWeight: 'bold' },
    '.adoc-delimiter': { color: '#656d76' },
    '.adoc-literal, .adoc-source': { color: '#0a3069' },
    '.adoc-table': { color: '#116329' },
    '.adoc-list-marker': { color: '#cf222e' },
    '.adoc-strong': { fontWeight: 'bold' },
    '.adoc-emphasis': { fontStyle: 'italic' },
    '.adoc-monospace': { color: '#0a3069', backgroundColor: '#f6f8fa' },
    '.adoc-link': { color: '#0969da', textDecoration: 'underline' },
    '.adoc-macro': { color: '#8250df' },
    '.adoc-kbd': { color: '#0550ae', backgroundColor: '#eef6ff', borderRadius: '3px' },
    '.adoc-menu': { color: '#6639ba' },
    '.adoc-button': { color: '#8250df' },
    '.adoc-image-marker': { color: '#8250df' },
    '.adoc-image-target': { color: '#0550ae', textDecoration: 'underline' },
    '.adoc-image-alt': { color: '#656d76' },
    '.cm-hljs-keyword, .cm-hljs-selector-tag, .cm-hljs-built_in': { color: '#d73a49' },
    '.cm-hljs-string, .cm-hljs-symbol, .cm-hljs-bullet, .cm-hljs-addition': { color: '#032f62' },
    '.cm-hljs-number, .cm-hljs-literal': { color: '#005cc5' },
    '.cm-hljs-comment, .cm-hljs-quote, .cm-hljs-deletion': { color: '#6a737d', fontStyle: 'italic' },
    '.cm-hljs-title, .cm-hljs-section, .cm-hljs-name': { color: '#6f42c1' },
    '.cm-hljs-function, .cm-hljs-title.function_': { color: '#6f42c1' },
    '.cm-hljs-class, .cm-hljs-title.class_': { color: '#6f42c1' },
    '.cm-hljs-variable, .cm-hljs-template-variable, .cm-hljs-attribute': { color: '#e36209' },
    '.cm-hljs-meta, .cm-hljs-meta .cm-hljs-keyword': { color: '#d73a49' },
    '.cm-hljs-params': { color: '#24292e' },
    '.cm-hljs-regexp': { color: '#032f62' },
    '.cm-hljs-tag': { color: '#22863a' },
    '.cm-hljs-attr': { color: '#005cc5' },
  }),
]
