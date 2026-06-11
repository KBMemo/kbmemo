// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import MemoDirectorySidebarOpenController from "../memo_directory_sidebar_open_controller.js"

let application

beforeEach(async () => {
  document.body.replaceChildren()
  vi.stubGlobal("Turbo", { visit: vi.fn() })
  application = Application.start()
  application.register("memo-directory-sidebar-open", MemoDirectorySidebarOpenController)
  document.body.innerHTML = `
    <div
      data-controller="memo-directory-sidebar-open"
      data-memo-directory-sidebar-open-memo-path-value="/memos/1"
    >
      <button type="button" data-memo-directory-sidebar-open-target="button" data-action="click->memo-directory-sidebar-open#open">/Home/User one</button>
      <input type="hidden" data-memo-directory-parent-picker-target="hiddenInput">
    </div>
  `
  await Promise.resolve()
})

afterEach(() => {
  application?.stop()
  vi.unstubAllGlobals()
})

describe("memo-directory-sidebar-open", () => {
  it("enables the directory label button only when a directory is selected", () => {
    const button = document.querySelector("[data-memo-directory-sidebar-open-target='button']")
    const input = document.querySelector("[data-memo-directory-parent-picker-target='hiddenInput']")

    expect(button.disabled).toBe(true)
    expect(button.classList.contains("kb-text-secondary")).toBe(true)

    input.value = "42"
    input.dispatchEvent(new Event("change"))

    expect(button.disabled).toBe(false)
    expect(button.classList.contains("kb-inline-link")).toBe(true)
  })

  it("opens the memo path in the selected directory", () => {
    const button = document.querySelector("[data-memo-directory-sidebar-open-target='button']")
    const input = document.querySelector("[data-memo-directory-parent-picker-target='hiddenInput']")

    input.value = "42"
    input.dispatchEvent(new Event("change"))
    button.click()

    expect(window.Turbo.visit).toHaveBeenCalledWith("http://localhost:3000/memos/1?memo_directory_id=42")
  })
})
