// @vitest-environment happy-dom

import { beforeEach, describe, expect, it } from "vitest"
import {
  applyOpenDirectoryIds,
  openDirectoryIdsFromPanel,
  setBranchOpen
} from "../../memo_directory_nav_open.js"

beforeEach(() => {
  document.body.replaceChildren()
  document.body.innerHTML = `
    <div id="memos_list_panel">
      <div class="memo-directory-nav-details" data-memo-directory-id="1" data-memo-directory-nav-branch data-memo-directory-nav-open="true">
        <button type="button" class="memo-directory-nav-summary" aria-expanded="true" aria-controls="children-1">▶</button>
        <div class="memo-directory-nav-row"><a><span>Home</span></a></div>
        <ul id="children-1" class="kb-tree-children"><li>Child</li></ul>
      </div>
      <div class="memo-directory-nav-details" data-memo-directory-id="2" data-memo-directory-nav-branch data-memo-directory-nav-open="false">
        <button type="button" class="memo-directory-nav-summary" aria-expanded="false" aria-controls="children-2">▶</button>
        <div class="memo-directory-nav-row"><a><span>Share</span></a></div>
        <ul id="children-2" class="kb-tree-children" hidden><li>Child</li></ul>
      </div>
    </div>
  `
})

describe("memo directory nav open state", () => {
  it("collects open branch ids from custom branch state", () => {
    expect(openDirectoryIdsFromPanel()).toEqual(["1"])
  })

  it("applies stored open ids without hiding directory rows", () => {
    applyOpenDirectoryIds(["2"])

    const closed = document.querySelector("[data-memo-directory-id='1']")
    const opened = document.querySelector("[data-memo-directory-id='2']")

    expect(closed.dataset.memoDirectoryNavOpen).toBe("false")
    expect(closed.querySelector(".memo-directory-nav-summary").getAttribute("aria-expanded")).toBe("false")
    expect(closed.querySelector(".memo-directory-nav-row").hidden).toBe(false)
    expect(closed.querySelector(".kb-tree-children").hidden).toBe(true)

    expect(opened.dataset.memoDirectoryNavOpen).toBe("true")
    expect(opened.querySelector(".memo-directory-nav-summary").getAttribute("aria-expanded")).toBe("true")
    expect(opened.querySelector(".memo-directory-nav-row").hidden).toBe(false)
    expect(opened.querySelector(".kb-tree-children").hidden).toBe(false)
  })

  it("toggles only the child list when closing a branch", () => {
    const branch = document.querySelector("[data-memo-directory-id='1']")

    setBranchOpen(branch, false)

    expect(branch.dataset.memoDirectoryNavOpen).toBe("false")
    expect(branch.querySelector(".memo-directory-nav-summary").getAttribute("aria-expanded")).toBe("false")
    expect(branch.querySelector(".memo-directory-nav-row").hidden).toBe(false)
    expect(branch.querySelector(".kb-tree-children").hidden).toBe(true)
  })
})
