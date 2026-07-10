// @vitest-environment happy-dom
import { describe, expect, it } from "vitest"
import { replyFromTraceInteractions, resolveAssistantReply } from "../chat_interactions.js"

describe("resolveAssistantReply", () => {
  it("prefers explicit reply text", () => {
    expect(
      resolveAssistantReply({
        reply: "hello",
        trace: { interactions: [{ role: "response", text: "other" }] },
        streamedPreview: "stream"
      })
    ).toBe("hello")
  })

  it("falls back to generate step response in trace", () => {
    expect(
      resolveAssistantReply({
        reply: "",
        trace: {
          interactions: [
            { role: "response", step_key: "intent", text: '{"intent":"conversation"}' },
            { role: "response", step_key: "generate", text: "最終回答" }
          ]
        }
      })
    ).toBe("最終回答")
  })

  it("falls back to streamed preview", () => {
    expect(
      resolveAssistantReply({
        reply: "",
        trace: null,
        streamedPreview: "partial"
      })
    ).toBe("partial")
  })
})

describe("replyFromTraceInteractions", () => {
  it("uses the last generate response when present", () => {
    expect(
      replyFromTraceInteractions([
        { role: "response", step_key: "generate", text: "first" },
        { role: "response", step_key: "generate_escalated", text: "final" }
      ])
    ).toBe("final")
  })
})
