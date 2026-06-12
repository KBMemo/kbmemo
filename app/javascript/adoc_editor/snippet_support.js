export const MEMO_SOURCE_SNIPPETS = [
  {
    id: "heading",
    label: "見出し",
    detail: "== 見出し",
    keywords: ["section", "title", "見出し"],
    template: ({ selected }) => {
      if (selected) return collapseSelection(`== ${selected}`)
      return { text: "== 見出し", selectFrom: 3, selectTo: 6 }
    },
  },
  {
    id: "wiki-link",
    label: "WikiLink",
    detail: "[[リンク先]]",
    keywords: ["wiki", "wikilink", "memo", "link"],
    template: ({ selected }) => {
      if (selected) return collapseSelection(`[[${selected}]]`)
      return { text: "[[リンク先]]", selectFrom: 2, selectTo: 6 }
    },
  },
  {
    id: "wiki-link-label",
    label: "WikiLink 表示名",
    detail: "[[リンク先|表示名]]",
    keywords: ["wiki", "label", "alias", "display"],
    template: ({ selected }) => {
      if (selected) return { text: `[[${selected}|表示名]]`, selectFrom: selected.length + 3, selectTo: selected.length + 6 }
      return { text: "[[リンク先|表示名]]", selectFrom: 2, selectTo: 6 }
    },
  },
  {
    id: "link",
    label: "リンク",
    detail: "link:https://example.com[表示名]",
    keywords: ["url", "link", "リンク"],
    template: ({ selected }) => {
      if (selected) return { text: `link:https://example.com[${selected}]`, selectFrom: 5, selectTo: 24 }
      return { text: "link:https://example.com[表示名]", selectFrom: 5, selectTo: 24 }
    },
  },
  {
    id: "unordered-list",
    label: "箇条書き",
    detail: "* 項目",
    keywords: ["list", "ul", "bullet"],
    template: ({ selected }) => {
      if (selected) return collapseSelection(`* ${selected}`)
      return { text: "* 項目", selectFrom: 2, selectTo: 4 }
    },
  },
  {
    id: "checklist",
    label: "チェックリスト",
    detail: "* [ ] タスク",
    keywords: ["todo", "task", "check"],
    template: ({ selected }) => {
      if (selected) return collapseSelection(`* [ ] ${selected}`)
      return { text: "* [ ] タスク", selectFrom: 6, selectTo: 9 }
    },
  },
  {
    id: "code-block",
    label: "コードブロック",
    detail: "[source,language]",
    keywords: ["source", "code", "listing"],
    template: ({ selected }) => {
      const body = selected || "code"
      return {
        text: `[source,language]\n----\n${body}\n----`,
        selectFrom: selected ? 8 : 24,
        selectTo: selected ? 16 : 28,
      }
    },
  },
  {
    id: "admonition",
    label: "NOTE",
    detail: "NOTE: メモ",
    keywords: ["note", "tip", "important", "warning", "admonition"],
    template: ({ selected }) => {
      if (selected) return collapseSelection(`NOTE: ${selected}`)
      return { text: "NOTE: メモ", selectFrom: 6, selectTo: 8 }
    },
  },
  {
    id: "quote",
    label: "引用",
    detail: "____",
    keywords: ["quote", "blockquote"],
    template: ({ selected }) => {
      const body = selected || "引用文"
      return { text: `____\n${body}\n____`, selectFrom: 5, selectTo: 5 + body.length }
    },
  },
  {
    id: "table",
    label: "テーブル",
    detail: "|===",
    keywords: ["table"],
    template: () => ({
      text: "|===\n|見出し1 |見出し2\n\n|値1 |値2\n|===",
      selectFrom: 5,
      selectTo: 9,
    }),
  },
  {
    id: "image",
    label: "画像",
    detail: "image::path/to/image.png[alt=説明]",
    keywords: ["image", "img", "picture"],
    template: () => ({
      text: "image::path/to/image.png[alt=説明]",
      selectFrom: 7,
      selectTo: 24,
    }),
  },
  {
    id: "tsuzura-image",
    label: "Tsuzura 画像",
    detail: "image::media:MEDIA_ID[alt=説明]",
    keywords: ["tsuzura", "media", "photo"],
    template: () => ({
      text: "image::media:MEDIA_ID[alt=説明]",
      selectFrom: 13,
      selectTo: 21,
    }),
  },
]

export function filterMemoSourceSnippets(query, snippets = MEMO_SOURCE_SNIPPETS) {
  const needle = normalizeQuery(query)
  if (!needle) return snippets

  return snippets.filter((snippet) => {
    const haystack = [
      snippet.label,
      snippet.detail,
      ...(snippet.keywords ?? []),
    ].join(" ")
    return normalizeQuery(haystack).includes(needle)
  })
}

export function snippetInsertion(snippet, selected = "") {
  const result = snippet.template({ selected })
  return {
    text: result.text,
    selectFrom: clampSelection(result.selectFrom, result.text.length),
    selectTo: clampSelection(result.selectTo, result.text.length),
  }
}

export function applySnippetToEditorView(view, snippet) {
  const { state } = view
  const { from, to } = state.selection.main
  const selected = from === to ? "" : state.doc.sliceString(from, to)
  const insertion = snippetInsertion(snippet, selected)
  view.dispatch({
    changes: { from, to, insert: insertion.text },
    selection: {
      anchor: from + insertion.selectFrom,
      head: from + insertion.selectTo,
    },
    scrollIntoView: true,
  })
  view.focus()
}

function collapseSelection(text) {
  return { text, selectFrom: text.length, selectTo: text.length }
}

function normalizeQuery(value) {
  return String(value ?? "").trim().toLowerCase()
}

function clampSelection(value, length) {
  return Math.max(0, Math.min(Number(value) || 0, length))
}
