// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import MemoAiPanelController from "../memo_ai_panel_controller.js"

let application

async function mount({ modelOptions = false } = {}) {
  document.head.innerHTML = '<meta name="csrf-token" content="test-token">'
  document.body.innerHTML = `
    <section
      data-controller="memo-ai-panel"
      data-memo-ai-panel-chat-url-value="/memos/1/ai_chat"
      ${modelOptions ? 'data-memo-ai-panel-model-options-url-value="/chat_server/model_options"' : ""}
    >
      <select data-memo-ai-panel-target="modelRole" data-action="change->memo-ai-panel#modelRoleChanged">
        <option value="main">Main · large-model</option>
        <option value="fast_chat">Fast chat · small-model</option>
      </select>
      <div data-memo-ai-panel-target="messages"></div>
      <p class="hidden" data-memo-ai-panel-target="error"></p>
      <textarea data-memo-ai-panel-target="input"></textarea>
      <button type="button" data-memo-ai-panel-target="sendButton" data-action="memo-ai-panel#send">送信</button>
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
})
