// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import NotebookMemoTreeController from "../notebook_memo_tree_controller.js"

let application
let controller

beforeEach(async () => {
  document.head.innerHTML = '<meta name="csrf-token" content="test-token">'
  document.body.innerHTML = `
    <section
      data-controller="notebook-memo-tree"
      data-notebook-memo-tree-reorder-url-value="/notebooks/1/reorder_memos"
    >
      <p class="hidden" role="status" data-notebook-memo-tree-target="status"></p>
    </section>
  `
  application = Application.start()
  application.register("notebook-memo-tree", NotebookMemoTreeController)
  await vi.waitFor(() => {
    const element = document.querySelector("[data-controller='notebook-memo-tree']")
    controller =
      application.getControllerForElementAndIdentifier(element, "notebook-memo-tree")
    expect(controller).not.toBeNull()
  })
})

afterEach(() => {
  application?.stop()
  vi.unstubAllGlobals()
  document.body.replaceChildren()
})

describe("notebook-memo-tree", () => {
  it("announces a successful reorder", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      headers: new Headers({ "Content-Type": "application/json" })
    })))

    await controller._patchMove("2", null, 1)

    const status = document.querySelector("[role='status']")
    expect(status.textContent).toBe("並べ替えました。")
    expect(status.classList.contains("kb-status-success")).toBe(true)
  })

  it("keeps an error visible and allows another reorder", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: false,
      json: async () => ({ error: "移動先が不正です。" })
    })))

    await controller._patchMove("2", "3", 0)

    const status = document.querySelector("[role='status']")
    expect(status.textContent).toBe("移動先が不正です。")
    expect(status.classList.contains("kb-status-danger")).toBe(true)
    expect(document.documentElement.classList.contains("notebook-memo-tree-dragging")).toBe(false)
  })
})
