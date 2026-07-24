// @vitest-environment happy-dom
import { describe, expect, it } from "vitest"
import AgentChatController from "../agent_chat_controller.js"

function controllerInstance() {
  return Object.create(AgentChatController.prototype)
}

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
})
