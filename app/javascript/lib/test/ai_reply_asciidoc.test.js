import { describe, expect, it } from "vitest"
import { asciiDocFromAiReply, jsonEnvelope } from "../ai_reply_asciidoc.js"

describe("asciiDocFromAiReply", () => {
  it("prefers edit.content over the chat reply", () => {
    expect(
      asciiDocFromAiReply("短い説明", { target: "none", content: "== Section\n\nBody" })
    ).toBe("== Section\n\nBody")
  })

  it("unwraps a JSON envelope into AsciiDoc", () => {
    const raw = JSON.stringify({
      reply: "追記しました",
      edit: { target: "none", content: "* item\n* two" }
    })
    expect(asciiDocFromAiReply(raw)).toBe("* item\n* two")
    expect(jsonEnvelope(raw)).toBe(true)
  })

  it("uses reply when it is already AsciiDoc", () => {
    expect(asciiDocFromAiReply("== Title\n\nHello")).toBe("== Title\n\nHello")
    expect(jsonEnvelope("== Title\n\nHello")).toBe(false)
  })

  it("does not insert a JSON envelope as memo body", () => {
    const raw = '{"reply":"ok","edit":{"target":"none","content":""}}'
    expect(asciiDocFromAiReply(raw)).toBe("ok")
    expect(asciiDocFromAiReply(raw)).not.toContain('"edit"')
  })

  it("converts markdown headings lists and links to AsciiDoc", () => {
    const markdown = "## Hello\n\n- first\n- **second**\n\n[Example](https://example.com)"
    expect(asciiDocFromAiReply(markdown)).toBe(
      "== Hello\n\n* first\n* *second*\n\nhttps://example.com[Example]"
    )
  })

  it("converts markdown fenced code to an AsciiDoc source block", () => {
    const markdown = "```ruby\nputs 1\n```"
    expect(asciiDocFromAiReply(markdown)).toBe("[source,ruby]\n----\nputs 1\n----")
  })

  it("leaves AsciiDoc source unchanged", () => {
    const adoc = "== Hello\n\n* first\n* *second*"
    expect(asciiDocFromAiReply(adoc)).toBe(adoc)
  })

  it("leaves AsciiDoc source blocks unchanged", () => {
    const adoc = "[source,ruby]\n----\nputs 1\n----"
    expect(asciiDocFromAiReply(adoc)).toBe(adoc)
  })

  it("converts markdown edit.content used for live editor apply", () => {
    expect(
      asciiDocFromAiReply("短い説明", { target: "section", content: "## Hello\n\n- item" })
    ).toBe("== Hello\n\n* item")
  })

  it("unwraps a JSON envelope with unescaped newlines in content", () => {
    const raw = '{"reply":"注目選手に関する分析セクションを追加しました。各チームの戦術的な強みを活かすキープレイヤーを想定して追記しています。","edit":{"target":"section","content":"\n\n== 注目選手\n\n* キープレイヤー\n"}}'
    expect(asciiDocFromAiReply(raw)).toBe("== 注目選手\n\n* キープレイヤー")
    expect(asciiDocFromAiReply(raw)).not.toContain('{"reply"')
    expect(jsonEnvelope(raw)).toBe(true)
  })

  it("strips a truncated JSON envelope prefix from appended text", () => {
    const raw = '{"reply":"注目選手に関する分析セクションを追加しました。","edit":{"target":"section","content":"\n\n== 注目選手\n\n* キープレイヤー'
    expect(asciiDocFromAiReply(raw)).toBe("== 注目選手\n\n* キープレイヤー")
    expect(asciiDocFromAiReply(raw)).not.toContain('"edit"')
  })
})
