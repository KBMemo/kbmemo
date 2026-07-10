// @vitest-environment happy-dom
import { describe, expect, it } from "vitest"
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

  it("renders safe links only", () => {
    const html = render("[Example](https://example.com) and [bad](javascript:alert(1))")

    expect(html.querySelector("a")?.href).toBe("https://example.com/")
    expect(html.textContent).toContain("bad")
    expect(html.querySelectorAll("a")).toHaveLength(1)
  })
})
