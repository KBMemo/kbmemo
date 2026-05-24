import { StateEffect } from "@codemirror/state"

/** 編集中（raw 表示）の stem ブロック（block.startLine） */
export const setStemActiveBlock = StateEffect.define()

export function activateStemBlock(view, blockStartLine, editLineNo) {
  const line = Math.min(Math.max(1, editLineNo), view.state.doc.lines)
  const pos = view.state.doc.line(line).from
  view.dispatch({
    effects: setStemActiveBlock.of(blockStartLine),
    selection: { anchor: pos, head: pos },
    scrollIntoView: true
  })
}
