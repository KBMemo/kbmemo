// @vitest-environment happy-dom

import { describe, expect, it } from "vitest"
import MemoDraftController from "../memo_draft_controller.js"
import MemoShowMetadataController from "../memo_show_metadata_controller.js"

function controllerWithInput(ControllerClass) {
  const controller = Object.create(ControllerClass.prototype)
  const input = document.createElement("input")
  input.dataset.tagSuggestionsList = "tag-options"
  controller.hasTagInputTarget = true
  controller.tagInputTarget = input
  return { controller, input }
}

describe.each([
  [ "memo draft", MemoDraftController ],
  [ "memo show metadata", MemoShowMetadataController ]
])("%s tag suggestions", (_name, ControllerClass) => {
  it("associates the datalist only after text is entered", () => {
    const { controller, input } = controllerWithInput(ControllerClass)

    controller.syncTagSuggestionsList()
    expect(input.hasAttribute("list")).toBe(false)

    input.value = "ra"
    controller.syncTagSuggestionsList()
    expect(input.getAttribute("list")).toBe("tag-options")

    input.value = ""
    controller.syncTagSuggestionsList()
    expect(input.hasAttribute("list")).toBe(false)
  })
})
