import { Prec } from "@codemirror/state"
import { keymap } from "@codemirror/view"
import {
  listContinuationMarker,
  parseListLine
} from "./list_syntax"

const FENCE_LINE = /^```/

function inFencedBlock(doc, lineNo) {
  let inFenced = false
  for (let n = 1; n <= lineNo; n++) {
    if (FENCE_LINE.test(doc.line(n).text)) inFenced = !inFenced
  }
  return inFenced
}

function continueListOnEnter(view) {
  const { state } = view
  const main = state.selection.main
  if (!main.empty) return false

  const head = main.head
  const line = state.doc.lineAt(head)
  if (inFencedBlock(state.doc, line.number)) return false

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

  const marker = listContinuationMarker(state.doc, line.number, parsed)
  const insert = `\n${parsed.indent}${marker} `
  view.dispatch({
    changes: { from: head, to: head, insert },
    selection: { anchor: head + insert.length }
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
