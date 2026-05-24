import { autocompletion, startCompletion } from "@codemirror/autocomplete"
import { EditorView } from "@codemirror/view"
import { getCsrfToken } from '../hostConfig.js'

/** [[ と ]]（または | より前）に挟まれたスラッグ文字列全体 */
function wikiSlugSpan(text, innerStart, closeIdx) {
  const raw = closeIdx === -1 ? text.slice(innerStart) : text.slice(innerStart, closeIdx)
  const pipeAt = raw.indexOf("|")
  const query = pipeAt === -1 ? raw : raw.slice(0, pipeAt)
  const slugEndOffset = innerStart + (pipeAt === -1 ? raw.length : pipeAt)
  return { query, slugEndOffset }
}

/**
 * [[query または [[既存リンク]] 内を編集中ならコンテキストを返す。
 * 検索クエリはカーソル左ではなく [[ … ]] 内のスラッグ全体。
 * 既存リンクのときは [[ ... ]] 全体（閉じ括弧まで）を置換範囲にする。
 */
export function wikiLinkContext(state, pos) {
  const line = state.doc.lineAt(pos)
  const lineStart = line.from
  const text = line.text
  const offset = pos - lineStart

  const before = text.slice(0, offset)
  const openIdx = before.lastIndexOf("[[")
  if (openIdx === -1) return null

  const innerStart = openIdx + 2
  const closeIdx = text.indexOf("]]", innerStart)
  const { query, slugEndOffset } = wikiSlugSpan(text, innerStart, closeIdx)

  if (closeIdx === -1) {
    if (offset < innerStart || offset > slugEndOffset) return null
    return {
      query,
      from: lineStart + innerStart,
      to: lineStart + slugEndOffset,
      replaceClosing: false
    }
  }

  const linkEnd = closeIdx + 2
  if (pos > lineStart + linkEnd) return null
  if (offset < innerStart || offset > slugEndOffset) return null

  return {
    query,
    from: lineStart + innerStart,
    to: lineStart + closeIdx,
    replaceClosing: true
  }
}

function wikiCompletionInsert(state, from, to, itemInsert, replaceClosing) {
  if (replaceClosing) return itemInsert

  const ahead = state.doc.sliceString(to, Math.min(to + 2, state.doc.length))
  if (ahead === "]]") return itemInsert

  const replaced = state.doc.sliceString(from, to)
  if (replaced.endsWith("]]") && replaced.length > 2) {
    return itemInsert
  }
  return `${itemInsert}]]`
}

let fetchSeq = 0

async function fetchWikiCompletions(url, memoId, query) {
  if (!url) return []

  const endpoint = new URL(url, window.location.origin)
  endpoint.searchParams.set("q", query)
  if (memoId) endpoint.searchParams.set("memo_id", String(memoId))

  const token = getCsrfToken()
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

    return {
      from: link.from,
      to: link.to,
      filter: false,
      options: items.map((item) => ({
        label: item.label ?? item.insert,
        detail: item.detail,
        apply: (view, _completion, from, end) => {
          const replaceClosing =
            view.state.doc.sliceString(end, end + 2) === "]]" ||
            view.state.doc.sliceString(end - 2, end) === "]]"
          const insert = wikiCompletionInsert(
            view.state,
            from,
            end,
            item.insert,
            replaceClosing
          )
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
