// @vitest-environment happy-dom
import { describe, expect, it } from "vitest"
import {
  buildChatActivity,
  formatChatDuration,
  formatChatDurationMs
} from "../chat_activity.js"

describe("chat_activity", () => {
  it("formats durations", () => {
    expect(formatChatDuration(4.2)).toBe("4.2秒")
    expect(formatChatDurationMs(65000)).toBe("1分5秒")
  })

  it("renders completed trace with stats and steps", () => {
    const panel = buildChatActivity({
      trace: {
        total_elapsed_ms: 1200,
        stats: [
          { label: "モデル", value: "gemma-4-e4b" },
          { label: "経過", value: "1.2秒" }
        ],
        steps: [
          {
            key: "intent",
            label: "Intent 分類",
            status: "completed",
            elapsed_ms: 200,
            detail: "rag_lookup (92%)"
          }
        ]
      }
    })

    expect(panel.querySelector(".kb-ai-chat-stats")).toBeTruthy()
    expect(panel.querySelectorAll(".kb-ai-chat-step")).toHaveLength(1)
    expect(panel.textContent).toContain("gemma-4-e4b")
    expect(panel.textContent).toContain("rag_lookup")
  })

  it("renders running activity with default steps", () => {
    const panel = buildChatActivity({ running: true, elapsedMs: 500 })
    expect(panel.classList.contains("kb-ai-chat-activity-running")).toBe(true)
    expect(panel.querySelectorAll(".kb-ai-chat-step")).toHaveLength(5)
    expect(panel.textContent).toContain("画像解析")
    expect(panel.textContent).toContain("処理中")
  })
})
