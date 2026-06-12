import { describe, expect, it } from "vitest"
import {
  MEMO_SOURCE_SNIPPETS,
  filterMemoSourceSnippets,
  snippetInsertion,
} from "../snippet_support.js"

describe("memo source snippet support", () => {
  it("filters snippets by label, detail, and keywords", () => {
    expect(filterMemoSourceSnippets("wiki").map((snippet) => snippet.id)).toContain("wiki-link")
    expect(filterMemoSourceSnippets("source").map((snippet) => snippet.id)).toContain("code-block")
    expect(filterMemoSourceSnippets("photo").map((snippet) => snippet.id)).toEqual(["tsuzura-image"])
  })

  it("wraps selected text for wiki links", () => {
    const snippet = findSnippet("wiki-link")

    expect(snippetInsertion(snippet, "home/example")).toEqual({
      text: "[[home/example]]",
      selectFrom: 16,
      selectTo: 16,
    })
  })

  it("selects the editable placeholder when inserting an empty wiki link", () => {
    const snippet = findSnippet("wiki-link")

    expect(snippetInsertion(snippet, "")).toEqual({
      text: "[[リンク先]]",
      selectFrom: 2,
      selectTo: 6,
    })
  })

  it("keeps selected text as the body of a code block and selects the language", () => {
    const snippet = findSnippet("code-block")

    expect(snippetInsertion(snippet, "puts :ok")).toEqual({
      text: "[source,language]\n----\nputs :ok\n----",
      selectFrom: 8,
      selectTo: 16,
    })
  })
})

function findSnippet(id) {
  const snippet = MEMO_SOURCE_SNIPPETS.find((candidate) => candidate.id === id)
  if (!snippet) throw new Error(`Missing snippet: ${id}`)
  return snippet
}
