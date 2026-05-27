import { Prec } from '@codemirror/state'
import { keymap } from '@codemirror/view'
import {
  indentForLiteralContinuation,
  isBlankLine,
  isIndentLiteralBlock,
} from '@kbmemo/adoc-codemirror'
import { parseListLine } from './list_syntax.js'

function isWysiwygBlockSourceEditor(view) {
  return Boolean(view.dom.closest('.wysiwyg-source-editor'))
}

/**
 * @param {{ onSplitToParagraph?: (view: import('@codemirror/view').EditorView) => void }} [options]
 */
export function literalParagraphContinuationExtension({ onSplitToParagraph } = {}) {
  return Prec.high(
    keymap.of([
      {
        key: 'Enter',
        run: (view) => continueWysiwygParagraphOnEnter(view, onSplitToParagraph),
      },
    ]),
  )
}

/**
 * @param {import('@codemirror/view').EditorView} view
 * @param {(view: import('@codemirror/view').EditorView) => void} [onSplitToParagraph]
 */
function continueWysiwygParagraphOnEnter(view, onSplitToParagraph) {
  if (!isWysiwygBlockSourceEditor(view)) return false

  const { state } = view
  const main = state.selection.main
  if (!main.empty) return false

  const doc = state.doc.toString()
  const head = main.head
  const line = state.doc.lineAt(head)
  const lineIndex = line.number - 1
  const lines = doc.split('\n')
  const atLineEnd = head >= line.from + line.text.trimEnd().length

  if (!atLineEnd) return false

  if (isBlankLine(line.text)) {
    onSplitToParagraph?.(view)
    return true
  }

  if (parseListLine(line.text)) return false

  if (isIndentLiteralBlock(doc)) {
    const indent = indentForLiteralContinuation(lines, lineIndex)
    const insert = `\n${indent}`
    view.dispatch({
      changes: { from: head, to: head, insert },
      selection: { anchor: head + insert.length },
    })
    return true
  }

  view.dispatch({
    changes: { from: head, to: head, insert: '\n' },
    selection: { anchor: head + 1 },
  })
  return true
}
