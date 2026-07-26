// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, describe, expect, it, vi } from "vitest"
import MemoDirectoryPathSearchController from "../memo_directory_path_search_controller.js"

let application

async function mount() {
  const options = Array.from(
    { length: 15 },
    (_, index) => `
      <button
        id="directory-option-${index}"
        class="hidden"
        type="button"
        role="option"
        data-directory-display-path="/home/Freddie/project-${index}"
        data-directory-path="/home/project-${index}"
        data-search-text="/home/project-${index} /Home/Project ${index}"
        data-memo-directory-path-search-target="option"
        data-action="mousedown->memo-directory-path-search#keepOpen click->memo-directory-path-search#select"
      >Project ${index}</button>
    `
  ).join("")
  document.body.innerHTML = `
    <form
      data-controller="memo-directory-path-search"
      data-memo-directory-path-search-target="form"
      data-action="submit->memo-directory-path-search#prepareSubmit"
    >
      <input
        role="combobox"
        aria-expanded="false"
        data-memo-directory-path-search-target="input"
        data-action="input->memo-directory-path-search#input keydown->memo-directory-path-search#keydown"
      >
      <input type="hidden" data-memo-directory-path-search-target="hiddenInput">
      <div class="hidden" data-memo-directory-path-search-target="options">${options}</div>
    </form>
  `
  application = Application.start()
  application.register("memo-directory-path-search", MemoDirectoryPathSearchController)
  await vi.waitFor(() => {
    expect(
      application.getControllerForElementAndIdentifier(
        document.querySelector("form"),
        "memo-directory-path-search"
      )
    ).not.toBeNull()
  })
}

afterEach(() => {
  application?.stop()
  document.body.replaceChildren()
})

describe("memo-directory-path-search", () => {
  it("shows at most ten matching directory candidates", async () => {
    await mount()
    const input = document.querySelector("input")
    input.value = "project"
    input.dispatchEvent(new Event("input", { bubbles: true }))

    const visible = [...document.querySelectorAll("[role='option']")]
      .filter((option) => !option.classList.contains("hidden"))
    expect(visible).toHaveLength(10)
    expect(input.getAttribute("aria-expanded")).toBe("true")
  })

  it("allows keyboard selection within the limited candidates", async () => {
    await mount()
    const input = document.querySelector("input")
    const form = document.querySelector("form")
    form.requestSubmit = vi.fn()
    input.value = "project"
    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }))
    expect(input.getAttribute("aria-activedescendant")).toBe("directory-option-0")
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))

    expect(input.value).toBe("/home/Freddie/project-0")
    expect(document.querySelector("input[type='hidden']").value).toBe("/home/project-0")
    expect(form.requestSubmit).toHaveBeenCalledOnce()
  })

  it("submits the internal path when the display path is typed", async () => {
    await mount()
    const input = document.querySelector("input")
    const hiddenInput = document.querySelector("input[type='hidden']")

    input.value = "/home/Freddie/project-1"
    input.dispatchEvent(new Event("input", { bubbles: true }))

    expect(hiddenInput.value).toBe("/home/project-1")
  })

  it("refreshes the submitted path from the final input value", async () => {
    await mount()
    const form = document.querySelector("form")
    const input = document.querySelector("input")
    const hiddenInput = document.querySelector("input[type='hidden']")
    input.value = "/home/project-12"
    hiddenInput.value = "/home/project-1"

    form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))

    expect(hiddenInput.value).toBe("/home/project-12")
  })
})
