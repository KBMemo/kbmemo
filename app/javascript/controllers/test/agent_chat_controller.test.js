// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest"
import AgentChatController from "../agent_chat_controller.js"

function controllerInstance() {
  return Object.create(AgentChatController.prototype)
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe("AgentChatController image generation state", () => {
  it("replaces draft images with final images after refinement completes", () => {
    const controller = controllerInstance()
    const entry = {
      role: "assistant",
      generated_images: [
        "https://nyoy.example/draft1.png",
        "https://nyoy.example/draft2.png"
      ],
      image_generation_watch: { id: 42, status: "awaiting_selection" }
    }

    controller.updateImageGenerationEntry(entry, {
      id: 42,
      status: "completed",
      image_urls: [ "https://nyoy.example/final.png" ]
    })

    expect(entry.generated_images).toEqual([ "https://nyoy.example/final.png" ])
    expect(entry.image_generation_watch).toEqual({
      id: 42,
      status: "completed",
      show_url: undefined
    })
  })

  it("keeps appending progress images outside draft selection", () => {
    const controller = controllerInstance()
    const entry = {
      role: "assistant",
      generated_images: [ "https://nyoy.example/first.png" ],
      image_generation_watch: { id: 7, status: "running" }
    }

    controller.updateImageGenerationEntry(entry, {
      id: 7,
      status: "completed",
      image_urls: [ "https://nyoy.example/final.png" ]
    })

    expect(entry.generated_images).toEqual([
      "https://nyoy.example/first.png",
      "https://nyoy.example/final.png"
    ])
  })
})

describe("AgentChatController memo references", () => {
  it("renders removable pending reference chips", () => {
    const controller = controllerInstance()
    const list = document.createElement("div")
    controller.pendingMemoReferences = [ { id: 1, title: "設計メモ" } ]
    controller.hasMemoReferenceListTarget = true
    controller.memoReferenceListTarget = list

    controller.renderMemoReferenceList()

    expect(list.textContent).toContain("設計メモ")
    list.querySelector("button").click()
    expect(controller.pendingMemoReferences).toEqual([])
    expect(list.textContent).toBe("")
  })

  it("links a reference title to the memo in a new tab", () => {
    const controller = controllerInstance()
    Object.defineProperties(controller, {
      hasMemoUrlTemplateValue: { value: true },
      memoUrlTemplateValue: { value: "/memos/__ID__" }
    })

    const node = controller.memoReferenceLabelNode({ id: 42, title: "設計メモ" })

    expect(node.tagName).toBe("A")
    expect(node.getAttribute("href")).toBe("/memos/42")
    expect(node.target).toBe("_blank")
    expect(node.rel).toBe("noopener")
  })
})

describe("AgentChatController keyboard send", () => {
  it("only sends on Ctrl or Command plus Enter outside IME composition", () => {
    const controller = controllerInstance()
    controller.send = vi.fn()

    controller.sendOnEnter(new KeyboardEvent("keydown", { key: "Enter" }))
    controller.sendOnEnter(
      new KeyboardEvent("keydown", { key: "Enter", ctrlKey: true, isComposing: true })
    )
    expect(controller.send).not.toHaveBeenCalled()

    controller.sendOnEnter(new KeyboardEvent("keydown", { key: "Enter", metaKey: true }))
    expect(controller.send).toHaveBeenCalledOnce()
  })
})

describe("AgentChatController initial memo reference", () => {
  it("reads references embedded by the server", () => {
    const controller = controllerInstance()
    const script = document.createElement("script")
    script.textContent = JSON.stringify([ { id: 1, title: "設計メモ" } ])
    controller.hasInitialMemoReferencesJsonTarget = true
    controller.initialMemoReferencesJsonTarget = script

    expect(controller.readInitialMemoReferences()).toEqual([ { id: 1, title: "設計メモ" } ])
  })
})

describe("AgentChatController reference persistence", () => {
  it("patches references for an existing conversation", async () => {
    const controller = controllerInstance()
    controller.conversationIdValue = "9"
    controller.memoReferencesUrlValue = "/agent_chat/memo_references"
    controller.pendingMemoReferences = [ { id: 42, title: "設計メモ" } ]
    controller.memoReferenceSyncVersion = 0
    controller.renderMemoReferenceList = vi.fn()
    controller.showError = vi.fn()
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      json: async () => ({
        memo_references: [ { id: 42, title: "設計メモ" } ]
      })
    })))

    await controller.persistMemoReferences()

    expect(fetch).toHaveBeenCalledOnce()
    const [url, options] = fetch.mock.calls[0]
    expect(url).toBe("/agent_chat/memo_references")
    expect(options.method).toBe("PATCH")
    expect(JSON.parse(options.body).memo_reference_ids).toEqual([ 42 ])
    expect(controller.showError).not.toHaveBeenCalled()
  })
})
