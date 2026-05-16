import { autocompletion, startCompletion } from "@codemirror/autocomplete"
import { EditorView } from "@codemirror/view"

// basicSetup の closeBrackets で [[ 入力時に ]] が先に入るため、補完時は既存の閉じ括弧を置換範囲に含める。
function wikiLinkReplaceEnd(state, pos) {
  const ahead = state.doc.sliceString(pos, Math.min(pos + 2, state.doc.length))
  if (ahead === "]]") return pos + 2
  return pos
}

/**
 * [[query または [[query]] の「query」部分を編集中（カーソルが ]] の直前）ならコンテキストを返す。
 */
export function wikiLinkContext(state, pos) {
  const line = state.doc.lineAt(pos)
  const lineStart = line.from
  const offset = pos - lineStart
  const before = line.text.slice(0, offset)
  const after = line.text.slice(offset)

  const openTail = before.match(/\[\[([^\]|]*)$/)
  if (openTail) {
    const query = openTail[1]
    return {
      query,
      from: pos - query.length,
      to: pos
    }
  }

  const openIdx = before.lastIndexOf("[[")
  if (openIdx === -1) return null

  const query = before.slice(openIdx + 2)
  if (query.includes("|") || query.includes("]]")) return null
  if (!after.startsWith("]]")) return null

  return {
    query,
    from: lineStart + openIdx + 2,
    to: pos
  }
}

function wikiCompletionInsert(state, from, to, itemInsert) {
  const replaced = state.doc.sliceString(from, to)
  if (replaced === "]]") return itemInsert + "]]"
  if (replaced.endsWith("]]") && replaced.length > 2) {
    return itemInsert + "]]"
  }
  return `${itemInsert}]]`
}

let fetchSeq = 0

async function fetchWikiCompletions(url, memoId, query) {
  if (!url) return []

  const endpoint = new URL(url, window.location.origin)
  endpoint.searchParams.set("q", query)
  if (memoId) endpoint.searchParams.set("memo_id", String(memoId))

  const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
  const seq = ++fetchSeq
  const res = await fetch(endpoint, {
    headers: {
      Accept: "application/json",
      ...(token ? { "X-CSRF-Token": token } : {})
    },
    credentials: "same-origin"
  })
  if (!res.ok) return []
  const data = await res.json()
  if (seq !== fetchSeq) return []
  return Array.isArray(data) ? data : []
}

export function wikiCompletionSource(getConfig) {
  return async (context) => {
    const link = wikiLinkContext(context.state, context.pos)
    if (!link) return null

    const { url, memoId } = getConfig()
    const items = await fetchWikiCompletions(url, memoId, link.query)
    if (items.length === 0 && !link.query && !context.explicit) return null

    const to = wikiLinkReplaceEnd(context.state, link.to)

    return {
      from: link.from,
      to,
      filter: false,
      options: items.map((item) => ({
        label: item.label ?? item.insert,
        detail: item.detail,
        apply: (view, _completion, from, end) => {
          const insert = wikiCompletionInsert(view.state, from, end, item.insert)
          view.dispatch({
            changes: { from, to: end, insert },
            selection: { anchor: from + insert.length }
          })
        }
      }))
    }
  }
}

/** 削除やカーソル移動で [[|]] になったときも候補を開く */
export function wikiCompletionActivationListener() {
  return EditorView.updateListener.of((update) => {
    if (!update.docChanged && !update.selectionSet) return
    const main = update.state.selection.main
    if (!main.empty) return
    if (!wikiLinkContext(update.state, main.head)) return
    startCompletion(update.view)
  })
}

export function wikiAutocompletion(getConfig) {
  return [
    autocompletion({
      override: [wikiCompletionSource(getConfig)],
      activateOnTyping: true,
      maxRenderedOptions: 12,
      icons: false
    }),
    wikiCompletionActivationListener()
  ]
}
