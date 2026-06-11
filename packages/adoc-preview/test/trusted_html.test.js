// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest"
import { setTrustedHTML } from "../trusted_html.js"

afterEach(() => {
  vi.unstubAllGlobals()
})

describe("@kbmemo/adoc-preview trusted_html", () => {
  it("uses the preview Trusted Types policy for trusted preview HTML", () => {
    const createPolicy = vi.fn((name, rules) => ({
      createHTML: (value) => rules.createHTML(value),
    }))
    vi.stubGlobal("trustedTypes", { createPolicy })

    const container = document.createElement("div")
    setTrustedHTML(container, "kbmemo-adoc-preview-html-test", "<p>Preview</p>")

    expect(createPolicy).toHaveBeenCalledWith("kbmemo-adoc-preview-html-test", expect.any(Object))
    expect(container.innerHTML).toBe("<p>Preview</p>")
  })
})
