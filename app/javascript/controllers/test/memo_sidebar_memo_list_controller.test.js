// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import MemoSidebarMemoListController from "../memo_sidebar_memo_list_controller.js"

let application
let controller

beforeEach(async () => {
  vi.stubGlobal("IntersectionObserver", class {
    observe() {}
    disconnect() {}
  })
  const rows = Array.from(
    { length: 15 },
    (_, index) => `<li id="sidebar_row_memo_${index + 1}">Memo ${index + 1}</li>`
  ).join("")
  document.body.innerHTML = `
    <div id="memo_sidebar_memo_list_scroll">
      <p id="memo_sidebar_list_count" data-total-count="25">15 / 25 件</p>
      <div
        data-controller="memo-sidebar-memo-list"
        data-memo-sidebar-memo-list-url-value="/memos/sidebar_memo_list"
        data-memo-sidebar-memo-list-offset-value="15"
        data-memo-sidebar-memo-list-has-more-value="true"
        data-memo-sidebar-memo-list-total-value="25"
        data-memo-sidebar-memo-list-params-value='{"sidebar_view":"tag","tag_ids":[7]}'
      >
        <ul id="memo_sidebar_memo_list">
          ${rows}
          <li
            id="memo_sidebar_memo_list_sentinel"
            data-memo-sidebar-memo-list-target="sentinel"
          ><span data-memo-sidebar-memo-list-target="sentinelLabel"></span></li>
        </ul>
      </div>
    </div>
  `
  application = Application.start()
  application.register("memo-sidebar-memo-list", MemoSidebarMemoListController)
  await vi.waitFor(() => {
    const element = document.querySelector("[data-controller='memo-sidebar-memo-list']")
    controller =
      application.getControllerForElementAndIdentifier(element, "memo-sidebar-memo-list")
    expect(controller).not.toBeNull()
  })
})

afterEach(() => {
  application?.stop()
  vi.unstubAllGlobals()
  document.body.replaceChildren()
})

describe("memo-sidebar-memo-list", () => {
  it("updates the shown count to the filtered total after loading the last page", async () => {
    const appendedRows = Array.from(
      { length: 10 },
      (_, index) => `<li id="sidebar_row_memo_${index + 16}">Memo ${index + 16}</li>`
    ).join("")
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true,
      text: async () => `
        <div id="memo_sidebar_memo_list_append_meta" data-has-more="false" data-next-offset="25"></div>
        ${appendedRows}
      `
    })))

    await controller.loadMore()

    expect(fetch.mock.calls[0][0]).toContain("sidebar_view=tag")
    expect(fetch.mock.calls[0][0]).toContain("tag_ids%5B%5D=7")
    expect(document.querySelectorAll("li[id^='sidebar_row_memo_']")).toHaveLength(25)
    expect(document.getElementById("memo_sidebar_list_count").textContent).toBe("25 / 25 件")
    expect(document.getElementById("memo_sidebar_memo_list_sentinel")).toBeNull()
  })
})
