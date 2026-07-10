// @vitest-environment happy-dom
import { describe, expect, it } from "vitest"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { appendChatMarkdown } from "../chat_markdown.js"

function render(markdown) {
  const container = document.createElement("div")
  appendChatMarkdown(container, markdown)
  return container
}

describe("chat_markdown", () => {
  it("renders headings lists and inline emphasis", () => {
    const html = render(
      "### Section\n\n* **Bold item**\n* plain\n\nParagraph with `code`."
    )

    expect(html.querySelector("h3")?.textContent).toBe("Section")
    expect(html.querySelectorAll("li")).toHaveLength(2)
    expect(html.querySelector("strong")?.textContent).toBe("Bold item")
    expect(html.querySelector("code")?.textContent).toBe("code")
    expect(html.querySelector("p")?.textContent).toContain("Paragraph")
  })

  it("preserves soft line breaks inside paragraphs", () => {
    const html = render("line one\nline two")
    const paragraph = html.querySelector("p")
    expect(paragraph?.querySelectorAll("br")).toHaveLength(1)
    expect(paragraph?.textContent).toContain("line one")
    expect(paragraph?.textContent).toContain("line two")
  })

  it("renders safe links only", () => {
    const html = render("[Example](https://example.com) and [bad](javascript:alert(1))")

    expect(html.querySelector("a")?.href).toBe("https://example.com/")
    expect(html.textContent).toContain("bad")
    expect(html.querySelectorAll("a")).toHaveLength(1)
  })

  it("renders headings and hr when newlines are present", () => {
    const html = render("導入文\n\n---\n\n### 見出し\n\n本文段落")

    expect(html.querySelector("hr")).toBeTruthy()
    expect(html.querySelector("h3")?.textContent).toBe("見出し")
    expect(html.textContent).toContain("導入文")
    expect(html.textContent).toContain("本文段落")
  })
})

describe("assistant reply fixture", () => {
  it("renders non-empty markdown for persisted assistant content", () => {
    const dir = dirname(fileURLToPath(import.meta.url))
    const fixturePath = join(dir, "fixtures", "assistant_reply.txt")
    let text
    try {
      text = readFileSync(fixturePath, "utf8").trim()
    } catch {
      text = "line one\nline two"
    }

    const bubble = document.createElement("div")
    appendChatMarkdown(bubble, text)

    expect(bubble.textContent.length).toBeGreaterThan(0)
  })
})
