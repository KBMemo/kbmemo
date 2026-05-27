// @vitest-environment happy-dom

import { describe, expect, it } from 'vitest'
import { EditorState } from '@codemirror/state'
import { EditorView } from '@codemirror/view'
import { literalParagraphContinuationExtension } from '../src/literal_paragraph_continuation.js'

/** @param {string} doc */
function viewWithDoc(doc) {
  const host = document.createElement('div')
  host.className = 'wysiwyg-source-editor'
  document.body.appendChild(host)

  const view = new EditorView({
    state: EditorState.create({
      doc,
      extensions: [literalParagraphContinuationExtension()],
    }),
    parent: host,
  })

  return { view, host }
}

describe('literalParagraphContinuationExtension hard breaks', () => {
  it('inserts trailing plus on Enter at end of normal paragraph line', () => {
    const { view, host } = viewWithDoc('Roses are red,')
    const head = view.state.doc.length
    view.dispatch({ selection: { anchor: head } })
    view.contentDOM.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }),
    )
    expect(view.state.doc.toString()).toBe('Roses are red, +\n')
    view.destroy()
    host.remove()
  })

  it('inserts newline on Enter at end of [%hardbreaks] paragraph line', () => {
    const { view, host } = viewWithDoc('[%hardbreaks]\nA ruby is red.')
    const head = view.state.doc.length
    view.dispatch({ selection: { anchor: head } })
    view.contentDOM.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }),
    )
    expect(view.state.doc.toString()).toBe('[%hardbreaks]\nA ruby is red.\n')
    view.destroy()
    host.remove()
  })
})
