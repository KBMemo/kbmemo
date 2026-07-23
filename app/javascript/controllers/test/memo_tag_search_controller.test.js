// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import MemoTagSearchController from "../memo_tag_search_controller.js"

let application
let requestSubmit

beforeEach(async () => {
  document.body.replaceChildren()
  requestSubmit = vi.fn()
  application = Application.start()
  application.register("memo-tag-search", MemoTagSearchController)
  document.body.innerHTML = `
    <search data-controller="memo-tag-search">
      <form data-memo-tag-search-target="form" data-action="submit->memo-tag-search#submit">
        <input
          type="search"
          role="combobox"
          aria-expanded="false"
          data-memo-tag-search-target="input"
          data-action="input->memo-tag-search#input keydown->memo-tag-search#keydown"
        >
        <button type="button" class="hidden" data-memo-tag-search-target="clear" data-action="memo-tag-search#clear">Clear</button>
      </form>
      <div class="hidden" data-memo-tag-search-target="options">
        <button type="button" class="hidden" data-memo-tag-search-target="option" data-tag-id="42" data-tag-name="AI" data-action="click->memo-tag-search#select">AI</button>
        <button type="button" class="hidden" data-memo-tag-search-target="option" data-tag-id="84" data-tag-name="Ａi" data-action="click->memo-tag-search#select">Ａi</button>
        <button type="button" class="hidden" data-memo-tag-search-target="option" data-tag-id="126" data-tag-name="Ruby" data-action="click->memo-tag-search#select">Ruby</button>
        <button type="button" class="hidden" data-memo-tag-search-target="option" data-tag-id="168" data-tag-name="雲" data-action="click->memo-tag-search#select">雲</button>
      </div>
    </search>
  `
  document.querySelector("form").requestSubmit = requestSubmit
  await Promise.resolve()
})

afterEach(() => {
  application?.stop()
})

describe("memo-tag-search", () => {
  it("matches case and full-width variants using Unicode normalization", () => {
    const input = document.querySelector("input[type='search']")
    input.value = "ai"
    input.dispatchEvent(new Event("input"))

    const visibleNames = Array.from(document.querySelectorAll("[data-memo-tag-search-target='option']"))
      .filter((option) => !option.classList.contains("hidden"))
      .map((option) => option.dataset.tagName)

    expect(visibleNames).toEqual(["AI", "Ａi"])
    expect(input.getAttribute("aria-expanded")).toBe("true")
  })

  it("adds and submits the selected candidate id", () => {
    const input = document.querySelector("input[type='search']")
    input.value = "ai"
    input.dispatchEvent(new Event("input"))
    document.querySelector("[data-tag-id='84']").click()

    expect(input.value).toBe("")
    expect(document.querySelector("input[name='tag_ids[]']").value).toBe("84")
    expect(requestSubmit).toHaveBeenCalledOnce()
  })

  it("shows only matching Japanese candidates", () => {
    const input = document.querySelector("input[type='search']")
    input.value = "雲"
    input.dispatchEvent(new Event("input"))

    const visibleNames = Array.from(document.querySelectorAll("[data-memo-tag-search-target='option']"))
      .filter((option) => !option.classList.contains("hidden"))
      .map((option) => option.dataset.tagName)

    expect(visibleNames).toEqual(["雲"])
  })

  it("keeps an existing tag when another tag is selected", () => {
    const form = document.querySelector("form")
    form.insertAdjacentHTML(
      "afterbegin",
      '<input type="hidden" name="tag_ids[]" value="42" data-tag-id="42" data-memo-tag-search-target="selectedTag">'
    )
    const input = document.querySelector("input[type='search']")
    input.value = "Ruby"
    input.dispatchEvent(new Event("input"))
    document.querySelector("[data-tag-id='126']").click()

    expect(
      Array.from(document.querySelectorAll("input[name='tag_ids[]']")).map((field) => field.value)
    ).toEqual(["42", "126"])
    expect(requestSubmit).toHaveBeenCalledOnce()
  })

  it("clears all selected tags and submits the empty filter", async () => {
    const form = document.querySelector("form")
    form.insertAdjacentHTML(
      "afterbegin",
      '<input type="hidden" name="tag_ids[]" value="126" data-tag-id="126" data-memo-tag-search-target="selectedTag">'
    )
    await Promise.resolve()
    const input = document.querySelector("input[type='search']")
    input.value = "Ruby"

    document.querySelector("[data-memo-tag-search-target='clear']").click()

    expect(input.value).toBe("")
    expect(document.querySelectorAll("input[name='tag_ids[]']")).toHaveLength(0)
    expect(requestSubmit).toHaveBeenCalledOnce()
  })
})
