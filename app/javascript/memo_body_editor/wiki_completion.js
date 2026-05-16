import { autocompletion } from "@codemirror/autocomplete"

const WIKI_OPEN = /\[\[([^\]|]*)$/

// basicSetup の closeBrackets で [[ 入力時に ]] が先に入るため、補完時は既存の閉じ括弧を置換範囲に含める。
function wikiLinkReplaceEnd(state, pos) {
  const ahead = state.doc.sliceString(pos, Math.min(pos + 2, state.doc.length))
  if (ahead === "]]") return pos + 2
  return pos
}

export function wikiLinkContext(state, pos) {
  const line = state.doc.lineAt(pos)
  const before = line.text.slice(0, pos - line.from)
  const match = before.match(WIKI_OPEN)
  if (!match) return null

  return {
    query: match[1],
    from: pos - match[1].length,
    to: pos
  }
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
          const insert = `${item.insert}]]`
          view.dispatch({
            changes: { from, to: end, insert },
            selection: { anchor: from + insert.length }
          })
        }
      }))
    }
  }
}

export function wikiAutocompletion(getConfig) {
  return autocompletion({
    override: [wikiCompletionSource(getConfig)],
    activateOnTyping: true,
    maxRenderedOptions: 12,
    icons: false
  })
}
