import { Prec } from "@codemirror/state"
import { keymap } from "@codemirror/view"
import { codeBlockByLine, scanCodeBlocks } from "./code_block_syntax"
import {
  listContinuationInsert,
  parseListLine
} from "./list_syntax"

function inCodeBlock(doc, lineNo) {
  return codeBlockByLine(scanCodeBlocks(doc)).has(lineNo)
}

function continueListOnEnter(view) {
  const { state } = view
  const main = state.selection.main
  if (!main.empty) return false

  const head = main.head
  const line = state.doc.lineAt(head)
  if (inCodeBlock(state.doc, line.number)) return false

  const trimmedEnd = line.from + line.text.trimEnd().length
  if (head < trimmedEnd) return false

  const parsed = parseListLine(line.text)
  if (!parsed) return false

  if (!parsed.content.trim()) {
    view.dispatch({
      changes: { from: line.from, to: line.to, insert: parsed.indent },
      selection: { anchor: line.from + parsed.indent.length }
    })
    return true
  }

  const marker = listContinuationInsert(state.doc, line.number, parsed)
  view.dispatch({
    changes: { from: head, to: head, insert: marker },
    selection: { anchor: head + marker.length }
  })
  return true
}

export function listContinuationExtension() {
  return Prec.high(
    keymap.of([
      {
        key: "Enter",
        run: continueListOnEnter
      }
    ])
  )
}
