// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import MemoDirectoryParentPickerController from "../memo_directory_parent_picker_controller.js"

let application

beforeEach(async () => {
  document.body.replaceChildren()
  application = Application.start()
  application.register("memo-directory-parent-picker", MemoDirectoryParentPickerController)
  document.body.innerHTML = pickerFixture()
  await Promise.resolve()
})

afterEach(() => {
  application?.stop()
})

describe("memo-directory-parent-picker", () => {
  it("opens from the toggle button and moves focus through visible options", () => {
    const toggle = document.querySelector("[data-memo-directory-parent-picker-target='toggleButton']")
    const panel = document.querySelector("[data-memo-directory-parent-picker-target='panel']")
    const first = document.querySelector("[data-directory-id='1']")
    const second = document.querySelector("[data-directory-id='2']")
    const hiddenChild = document.querySelector("[data-directory-id='3']")

    toggle.dispatchEvent(keydown("ArrowDown"))

    expect(panel.classList.contains("hidden")).toBe(false)
    expect(toggle.getAttribute("aria-expanded")).toBe("true")
    expect(document.activeElement).toBe(first)
    expect(first.tabIndex).toBe(0)
    expect(second.tabIndex).toBe(-1)
    expect(hiddenChild.tabIndex).toBe(-1)

    first.dispatchEvent(keydown("ArrowDown"))

    expect(document.activeElement).toBe(second)
    expect(first.tabIndex).toBe(-1)
    expect(second.tabIndex).toBe(0)
  })

  it("closes on Escape and returns focus to the toggle button", () => {
    const toggle = document.querySelector("[data-memo-directory-parent-picker-target='toggleButton']")
    const panel = document.querySelector("[data-memo-directory-parent-picker-target='panel']")

    toggle.dispatchEvent(keydown("ArrowDown"))
    panel.dispatchEvent(keydown("Escape"))

    expect(panel.classList.contains("hidden")).toBe(true)
    expect(toggle.getAttribute("aria-expanded")).toBe("false")
    expect(document.activeElement).toBe(toggle)
  })

  it("restores branch disclosure state before reopening", () => {
    const toggle = document.querySelector("[data-memo-directory-parent-picker-target='toggleButton']")
    const panel = document.querySelector("[data-memo-directory-parent-picker-target='panel']")
    const branch = document.querySelector("[data-directory-picker-branch]")
    const branchToggle = branch.querySelector(".kb-directory-picker-caret")
    const branchChildren = branch.querySelector(".kb-directory-picker-children")

    expect(branch.dataset.directoryPickerOpen).toBe("true")
    expect(branchToggle.getAttribute("aria-expanded")).toBe("true")
    expect(branchChildren.hidden).toBe(false)

    branchToggle.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))
    expect(branch.dataset.directoryPickerOpen).toBe("false")
    expect(branchChildren.hidden).toBe(true)
    expect(branch.querySelector("[data-directory-id='2']").hidden).toBe(false)

    toggle.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))
    toggle.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))

    expect(panel.classList.contains("hidden")).toBe(true)
    expect(branch.dataset.directoryPickerOpen).toBe("true")
    expect(branchToggle.getAttribute("aria-expanded")).toBe("true")
    expect(branchChildren.hidden).toBe(false)

    toggle.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))

    expect(panel.classList.contains("hidden")).toBe(false)
    expect(branch.dataset.directoryPickerOpen).toBe("true")
  })
})

function keydown(key) {
  return new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
}

function pickerFixture() {
  return `
    <div data-controller="memo-directory-parent-picker">
      <button
        type="button"
        data-memo-directory-parent-picker-target="toggleButton"
        data-action="click->memo-directory-parent-picker#toggle keydown->memo-directory-parent-picker#toggleKeydown"
        aria-expanded="false"
        aria-haspopup="listbox"
        aria-controls="picker-panel"
      >▼</button>
      <span data-memo-directory-parent-picker-target="pathLabel">選択してください</span>
      <input type="hidden" data-memo-directory-parent-picker-target="hiddenInput">
      <div id="picker-panel" class="hidden" data-memo-directory-parent-picker-target="panel" data-action="keydown->memo-directory-parent-picker#panelKeydown" role="listbox">
        <button type="button" role="option" aria-selected="false" tabindex="-1" data-memo-directory-parent-picker-target="option" data-action="click->memo-directory-parent-picker#select" data-directory-id="1" data-directory-path="Alpha" data-directory-full-path="/alpha">Alpha</button>
        <div class="kb-directory-picker-branch" data-directory-picker-branch data-directory-picker-initial-open="true" data-directory-picker-open="true">
          <button type="button" class="kb-directory-picker-caret" aria-expanded="true" data-action="memo-directory-parent-picker#toggleBranch">▶</button>
          <button type="button" role="option" aria-selected="false" tabindex="-1" data-memo-directory-parent-picker-target="option" data-action="click->memo-directory-parent-picker#select" data-directory-id="2" data-directory-path="Beta" data-directory-full-path="/beta">Beta</button>
          <ul class="kb-directory-picker-children">
            <li>
              <button type="button" role="option" aria-selected="false" tabindex="-1" data-memo-directory-parent-picker-target="option" data-action="click->memo-directory-parent-picker#select" data-directory-id="3" data-directory-path="Gamma" data-directory-full-path="/gamma">Gamma</button>
            </li>
          </ul>
        </div>
      </div>
    </div>
  `
}
