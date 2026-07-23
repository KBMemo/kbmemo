// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import MemoDraftController from "../memo_draft_controller.js"
import MemoMetadataSuggestionsController from "../memo_metadata_suggestions_controller.js"

let application

beforeEach(async () => {
  document.head.innerHTML = '<meta name="csrf-token" content="test-token">'
  document.body.innerHTML = `
    <section data-controller="memo-draft">
      <input value="現在のタイトル" data-memo-draft-target="title">
      <textarea data-memo-draft-target="body">現在の本文</textarea>
      <input value="Ruby" data-memo-draft-target="tagList">
      <div
        data-controller="memo-metadata-suggestions"
        data-memo-metadata-suggestions-url-value="/memos/1/metadata_suggestions"
      >
        <p class="hidden" data-memo-metadata-suggestions-target="status"></p>
        <button type="button" data-memo-metadata-suggestions-target="button" data-action="memo-metadata-suggestions#generate">AI</button>
        <div class="hidden" data-memo-metadata-suggestions-target="panel">
          <input data-memo-metadata-suggestions-target="title">
          <div data-memo-metadata-suggestions-target="tags"></div>
          <button type="button" data-action="memo-metadata-suggestions#apply">反映</button>
        </div>
      </div>
    </section>
  `
  application = Application.start()
  application.register("memo-metadata-suggestions", MemoMetadataSuggestionsController)
  await Promise.resolve()
})

afterEach(() => {
  application?.stop()
  vi.unstubAllGlobals()
})

describe("memo-metadata-suggestions", () => {
  it("shows returned suggestions and dispatches selected values", async () => {
    const fetchMock = vi.fn(async () => ({
      ok: true,
      json: async () => ({ title: "提案タイトル", tags: ["Ruby", "AI"] })
    }))
    vi.stubGlobal("fetch", fetchMock)
    const applied = vi.fn()
    document.querySelector("[data-controller='memo-draft']")
      .addEventListener("memo-metadata-suggestions:apply", applied)

    document.querySelector("[data-action$='#generate']").click()
    await vi.waitFor(() => {
      expect(document.querySelector("[data-memo-metadata-suggestions-target='title']").value)
        .toBe("提案タイトル")
    })
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toMatchObject({
      title: "現在のタイトル",
      body: "現在の本文",
      tags: ["Ruby"]
    })
    document.querySelector("[data-action$='#apply']").click()

    expect(applied).toHaveBeenCalledOnce()
    expect(applied.mock.calls[0][0].detail).toEqual({
      title: "提案タイトル",
      tags: ["Ruby", "AI"]
    })
  })

  it("applies the title and adds only new tags to the draft", () => {
    const context = {
      markFormInteracted: vi.fn(),
      hasTitleTarget: true,
      titleTarget: { value: "現在" },
      hasTitleManualFlagTarget: true,
      titleManualFlagTarget: { value: "0" },
      hasTagListTarget: true,
      tagListTarget: { value: "Ruby" },
      parseTagList: MemoDraftController.prototype.parseTagList,
      applyTags: vi.fn()
    }

    MemoDraftController.prototype.applyMetadataSuggestion.call(context, {
      detail: { title: "提案タイトル", tags: ["Ruby", "AI"] }
    })

    expect(context.titleTarget.value).toBe("提案タイトル")
    expect(context.titleManualFlagTarget.value).toBe("1")
    expect(context.applyTags).toHaveBeenCalledWith(["Ruby", "AI"])
  })

  it("keeps generating when Turbo navigation is cancelled", async () => {
    let requestSignal
    vi.stubGlobal("fetch", vi.fn((_url, options) => {
      requestSignal = options.signal
      return new Promise((_resolve, reject) => {
        options.signal.addEventListener("abort", () => {
          reject(new DOMException("Aborted", "AbortError"))
        })
      })
    }))
    vi.spyOn(window, "confirm").mockReturnValue(false)

    document.querySelector("[data-action$='#generate']").click()
    await vi.waitFor(() => expect(requestSignal).toBeDefined())
    const event = new CustomEvent("turbo:before-visit", { cancelable: true })
    document.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
    expect(requestSignal.aborted).toBe(false)
    expect(document.querySelector("[data-action$='#generate']").disabled).toBe(true)
  })

  it("aborts generation when Turbo navigation is confirmed", async () => {
    let requestSignal
    vi.stubGlobal("fetch", vi.fn((_url, options) => {
      requestSignal = options.signal
      return new Promise((_resolve, reject) => {
        options.signal.addEventListener("abort", () => {
          reject(new DOMException("Aborted", "AbortError"))
        })
      })
    }))
    vi.spyOn(window, "confirm").mockReturnValue(true)

    document.querySelector("[data-action$='#generate']").click()
    await vi.waitFor(() => expect(requestSignal).toBeDefined())
    const event = new CustomEvent("turbo:before-visit", { cancelable: true })
    document.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(false)
    expect(requestSignal.aborted).toBe(true)
    expect(document.querySelector("[data-action$='#generate']").disabled).toBe(false)
    expect(
      document.querySelector("[data-memo-metadata-suggestions-target='status']").textContent
    ).toBe("")
  })

  it("requests a browser warning before unloading while generating", async () => {
    vi.stubGlobal("fetch", vi.fn((_url, options) => (
      new Promise((_resolve, reject) => {
        options.signal.addEventListener("abort", () => {
          reject(new DOMException("Aborted", "AbortError"))
        })
      })
    )))

    document.querySelector("[data-action$='#generate']").click()
    await Promise.resolve()
    const event = new Event("beforeunload", { cancelable: true })
    window.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
  })

  it("aborts and resets generation before Turbo caches the page", async () => {
    let requestSignal
    vi.stubGlobal("fetch", vi.fn((_url, options) => {
      requestSignal = options.signal
      return new Promise((_resolve, reject) => {
        options.signal.addEventListener("abort", () => {
          reject(new DOMException("Aborted", "AbortError"))
        })
      })
    }))

    document.querySelector("[data-action$='#generate']").click()
    await vi.waitFor(() => expect(requestSignal).toBeDefined())
    document.dispatchEvent(new CustomEvent("turbo:before-cache"))

    expect(requestSignal.aborted).toBe(true)
    expect(document.querySelector("[data-action$='#generate']").disabled).toBe(false)
  })
})
