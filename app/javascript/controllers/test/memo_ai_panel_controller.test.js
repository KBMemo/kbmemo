// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import MemoAiPanelController from "../memo_ai_panel_controller.js"

let application

async function mount({ modelOptions = false, append = false } = {}) {
  document.head.innerHTML = '<meta name="csrf-token" content="test-token">'
  document.body.innerHTML = `
    <section
      data-controller="memo-ai-panel"
      data-memo-ai-panel-chat-url-value="/memos/1/ai_chat"
      ${append ? 'data-memo-ai-panel-append-url-value="/memos/1/append_ai_reply.json"' : ""}
      ${modelOptions ? 'data-memo-ai-panel-model-options-url-value="/chat_server/model_options"' : ""}
    >
      <select data-memo-ai-panel-target="modelRole" data-action="change->memo-ai-panel#modelRoleChanged">
        <option value="main">Main · large-model</option>
        <option value="fast_chat">Fast chat · small-model</option>
      </select>
      <div data-memo-ai-panel-target="messages"></div>
      <p class="hidden" data-memo-ai-panel-target="error"></p>
      <p class="hidden" role="status" data-memo-ai-panel-target="status"></p>
      <textarea data-memo-ai-panel-target="input" data-action="keydown->memo-ai-panel#sendOnEnter"></textarea>
      <button type="button" data-memo-ai-panel-target="sendButton" data-action="memo-ai-panel#send">送信</button>
      <button type="button" data-memo-ai-panel-target="insertButton" data-action="memo-ai-panel#insertLastReply">応答を末尾へ追記</button>
    </section>
  `
  application = Application.start()
  application.register("memo-ai-panel", MemoAiPanelController)
  await vi.waitFor(() => {
    const element = document.querySelector("[data-controller='memo-ai-panel']")
    expect(
      application.getControllerForElementAndIdentifier(element, "memo-ai-panel")
    ).not.toBeNull()
  })
}

beforeEach(() => {
  localStorage.clear()
})

afterEach(() => {
  application?.stop()
  vi.unstubAllGlobals()
  document.body.replaceChildren()
})

describe("memo-ai-panel", () => {
  it("sends the selected model role and displays the returned model", async () => {
    vi.stubGlobal("fetch", vi.fn(async (_url, options) => ({
      ok: true,
      json: async () => ({
        reply: "Response",
        backend: "local",
        model_role: "fast_chat",
        model: "small-model"
      }),
      requestBody: options.body
    })))
    await mount()

    const select = document.querySelector("select")
    select.value = "fast_chat"
    select.dispatchEvent(new Event("change", { bubbles: true }))
    document.querySelector("textarea").value = "Hello"
    document.querySelector("button").click()

    await vi.waitFor(() => expect(fetch).toHaveBeenCalledOnce())
    const body = JSON.parse(fetch.mock.calls[0][1].body)
    expect(body.model_role).toBe("fast_chat")
    await vi.waitFor(() => expect(document.body.textContent).toContain("small-model"))
    expect(localStorage.getItem("kbmemo_memo_ai_model_role_v1")).toBe("fast_chat")
  })

  it("restores a previously selected available role", async () => {
    localStorage.setItem("kbmemo_memo_ai_model_role_v1", "fast_chat")
    await mount()

    expect(document.querySelector("select").value).toBe("fast_chat")
  })

  it("refreshes model names while preserving the saved role", async () => {
    localStorage.setItem("kbmemo_memo_ai_model_role_v1", "fast_chat")
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      json: async () => ({
        options: [
          { role: "main", label: "Main", model: "new-large" },
          { role: "fast_chat", label: "Fast chat", model: "new-small" }
        ]
      })
    })))

    await mount({ modelOptions: true })
    await vi.waitFor(() => expect(document.querySelector("select").textContent).toContain("new-small"))

    expect(document.querySelector("select").value).toBe("fast_chat")
    expect(document.querySelector("select").textContent).not.toContain("small-model")
  })

  it("sends with Ctrl+Enter but keeps plain Enter for newlines", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      json: async () => ({ reply: "Response", backend: "local", model: "model" })
    })))
    await mount()
    const textarea = document.querySelector("textarea")
    textarea.value = "Hello"

    textarea.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
    expect(fetch).not.toHaveBeenCalled()

    textarea.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", ctrlKey: true, bubbles: true })
    )
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledOnce())
  })

  it("appends the last reply from the show panel", async () => {
    vi.stubGlobal("fetch", vi.fn(async (url) => ({
      ok: true,
      json: async () => (
        String(url).includes("ai_chat")
          ? { reply: "AI response", backend: "local", model: "model" }
          : { saved_at: "2026-07-26T00:00:00.000Z", display_as_draft: true }
      )
    })))
    await mount({ append: true })

    document.querySelector("textarea").value = "Hello"
    document.querySelector("[data-memo-ai-panel-target='sendButton']").click()
    await vi.waitFor(() => expect(document.body.textContent).toContain("AI response"))

    document.querySelector("[data-memo-ai-panel-target='insertButton']").click()
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(2))

    expect(fetch.mock.calls[1][0]).toBe("/memos/1/append_ai_reply.json")
    expect(fetch.mock.calls[1][1].method).toBe("PATCH")
    expect(JSON.parse(fetch.mock.calls[1][1].body)).toEqual({ content: "AI response" })
    await vi.waitFor(() =>
      expect(document.querySelector("[role='status']").textContent).toBe(
        "応答をメモ末尾へ追記しました。"
      )
    )
  })

  it("restores the append action after an append failure", async () => {
    vi.stubGlobal("fetch", vi.fn(async (url) => {
      if (String(url).includes("ai_chat")) {
        return {
          ok: true,
          json: async () => ({ reply: "AI response", backend: "local", model: "model" })
        }
      }
      return {
        ok: false,
        json: async () => ({ error: "メモを更新できませんでした。" })
      }
    }))
    await mount({ append: true })

    document.querySelector("textarea").value = "Hello"
    document.querySelector("[data-memo-ai-panel-target='sendButton']").click()
    await vi.waitFor(() => expect(document.body.textContent).toContain("AI response"))

    const insertButton = document.querySelector("[data-memo-ai-panel-target='insertButton']")
    insertButton.click()

    await vi.waitFor(() =>
      expect(document.querySelector("[data-memo-ai-panel-target='error']").textContent).toBe(
        "メモを更新できませんでした。"
      )
    )
    expect(insertButton.disabled).toBe(false)
    expect(insertButton.textContent).toBe("応答を末尾へ追記")
    expect(document.querySelector("[role='status']").textContent).toBe("")
  })
})
