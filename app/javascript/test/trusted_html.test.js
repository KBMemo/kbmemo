// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest"
import { setTrustedHTML, trustedHTML } from "../trusted_html.js"

afterEach(() => {
  vi.unstubAllGlobals()
})

describe("trusted_html", () => {
  it("routes trusted markup through a named Trusted Types policy when available", () => {
    const createPolicy = vi.fn((name, rules) => ({
      createHTML: (value) => rules.createHTML(value),
    }))
    vi.stubGlobal("trustedTypes", { createPolicy })

    const element = document.createElement("div")
    setTrustedHTML(element, "kbmemo-test-policy", "<strong>Safe</strong>")

    expect(createPolicy).toHaveBeenCalledTimes(1)
    expect(createPolicy).toHaveBeenCalledWith("kbmemo-test-policy", expect.any(Object))
    expect(element.innerHTML).toBe("<strong>Safe</strong>")

    trustedHTML("kbmemo-test-policy", "<em>Again</em>")
    expect(createPolicy).toHaveBeenCalledTimes(1)
  })

  it("falls back to plain innerHTML assignment when Trusted Types are unavailable", () => {
    vi.stubGlobal("trustedTypes", undefined)

    const element = document.createElement("div")
    setTrustedHTML(element, "kbmemo-fallback-policy", "<span>Fallback</span>")

    expect(element.innerHTML).toBe("<span>Fallback</span>")
  })
})
