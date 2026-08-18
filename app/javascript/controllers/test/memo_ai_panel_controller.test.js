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
      <div class="hidden" data-memo-ai-panel-target="messages"></div>
      <p class="hidden" data-memo-ai-panel-target="error"></p>
      <p class="hidden" role="status" data-memo-ai-panel-target="status"></p>
      <textarea data-memo-ai-panel-target="input" data-action="keydown->memo-ai-panel#sendOnEnter"></textarea>
      <button type="button" data-memo-ai-panel-target="sendButton" data-action="memo-ai-panel#send">送信</button>
      <button type="button" data-memo-ai-panel-target="insertButton" data-action="memo-ai-panel#insertLastReply">応答を末尾へ追記</button>
      <button type="button" data-action="memo-ai-panel#clearChat">履歴を消去</button>
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
  it("hides the messages pane until the first prompt is sent", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      json: async () => ({ reply: "Response", backend: "local", model: "model" })
    })))
    await mount()

    const messages = document.querySelector("[data-memo-ai-panel-target='messages']")
    expect(messages.classList.contains("hidden")).toBe(true)

    document.querySelector("textarea").value = "Hello"
    document.querySelector("[data-memo-ai-panel-target='sendButton']").click()
    await vi.waitFor(() => expect(messages.classList.contains("hidden")).toBe(false))
    expect(messages.textContent).toContain("Hello")

    document.querySelector("[data-action='memo-ai-panel#clearChat']").click()
    expect(messages.classList.contains("hidden")).toBe(true)
    expect(messages.childElementCount).toBe(0)
  })

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

  it("applies a selection edit to the body editor", async () => {
    const applyAiEdit = vi.fn(async () => ({ applied: true, target: "selection" }))
    const getEditContext = vi.fn(async () => ({
      body: "Hello world",
      selection: "Hello",
      active_unit: { kind: "paragraph", adoc: "Hello world" },
      section: null
    }))
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      json: async () => ({
        reply: "書き換えました",
        backend: "local",
        model: "model",
        edit: { target: "selection", content: "Hi" }
      })
    })))
    await mount()

    const element = document.querySelector("[data-controller='memo-ai-panel']")
    const controller = application.getControllerForElementAndIdentifier(element, "memo-ai-panel")
    controller.bodyEditorController = () => ({
      applyAiEdit,
      getEditContext,
      getSelectedText: () => "Hello"
    })

    document.querySelector("textarea").value = "直して"
    document.querySelector("[data-memo-ai-panel-target='sendButton']").click()

    await vi.waitFor(() => expect(applyAiEdit).toHaveBeenCalledOnce())
    expect(applyAiEdit).toHaveBeenCalledWith({ target: "selection", content: "Hi" })
    expect(JSON.parse(fetch.mock.calls[0][1].body).editor_context).toMatchObject({
      body: "Hello world",
      selection: "Hello"
    })
    await vi.waitFor(() =>
      expect(document.querySelector("[role='status']").textContent).toContain("選択範囲を書き換えました")
    )
  })

  it("does not apply when the edit target is none", async () => {
    const applyAiEdit = vi.fn()
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      json: async () => ({
        reply: "要点はこれです",
        backend: "local",
        model: "model",
        edit: { target: "none", content: "" }
      })
    })))
    await mount()

    const element = document.querySelector("[data-controller='memo-ai-panel']")
    const controller = application.getControllerForElementAndIdentifier(element, "memo-ai-panel")
    controller.bodyEditorController = () => ({
      applyAiEdit,
      getEditContext: async () => ({ body: "Hello", selection: "", active_unit: null, section: null })
    })

    document.querySelector("textarea").value = "要約して"
    document.querySelector("[data-memo-ai-panel-target='sendButton']").click()

    await vi.waitFor(() => expect(document.body.textContent).toContain("要点はこれです"))
    expect(applyAiEdit).not.toHaveBeenCalled()
    expect(document.querySelector("[role='status']").textContent).toBe("")
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
