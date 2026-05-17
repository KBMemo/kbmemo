import { StateEffect } from "@codemirror/state"

/** 編集中（raw 表示）の表ブロック（block.startLine） */
export const setTableActiveBlock = StateEffect.define()

export function activateTableBlock(view, blockStartLine, editLineNo) {
  const pos = view.state.doc.line(editLineNo).from
  view.dispatch({
    effects: setTableActiveBlock.of(blockStartLine),
    selection: { anchor: pos, head: pos },
    scrollIntoView: true
  })
}
