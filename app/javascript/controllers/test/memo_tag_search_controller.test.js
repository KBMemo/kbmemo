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
        <input type="hidden" data-memo-tag-search-target="tagId">
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

  it("submits the selected candidate id", () => {
    const input = document.querySelector("input[type='search']")
    input.value = "ai"
    input.dispatchEvent(new Event("input"))
    document.querySelector("[data-tag-id='84']").click()

    expect(input.value).toBe("Ａi")
    expect(document.querySelector("input[type='hidden']").value).toBe("84")
    expect(requestSubmit).toHaveBeenCalledOnce()
  })

  it("clears the selected tag and submits the empty filter", () => {
    const input = document.querySelector("input[type='search']")
    const tagId = document.querySelector("input[type='hidden']")
    input.value = "Ruby"
    tagId.value = "126"

    document.querySelector("[data-memo-tag-search-target='clear']").click()

    expect(input.value).toBe("")
    expect(tagId.value).toBe("")
    expect(requestSubmit).toHaveBeenCalledOnce()
  })
})
