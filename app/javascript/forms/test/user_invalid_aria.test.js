// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest"
import { initUserInvalidAriaSync } from "../user_invalid_aria.js"

function makeInput({ userInvalid = false } = {}) {
  const input = document.createElement("input")
  input.required = true

  const nativeMatches = input.matches.bind(input)
  vi.spyOn(input, "matches").mockImplementation((selector) => {
    if (selector === ":user-invalid") return userInvalid
    return nativeMatches(selector)
  })

  return {
    input,
    setUserInvalid(value) {
      userInvalid = value
    }
  }
}

describe("initUserInvalidAriaSync", () => {
  beforeEach(() => {
    document.body.replaceChildren()
    vi.stubGlobal("CSS", { supports: vi.fn(() => true) })
    initUserInvalidAriaSync()
  })

  it("sets aria-invalid when native user-invalid state appears", () => {
    const { input } = makeInput({ userInvalid: true })
    document.body.append(input)

    input.dispatchEvent(new Event("blur"))

    expect(input.getAttribute("aria-invalid")).toBe("true")
    expect(input.getAttribute("data-kb-client-invalid")).toBe("true")
  })

  it("clears only aria-invalid state created by the bridge", () => {
    const { input, setUserInvalid } = makeInput({ userInvalid: true })
    document.body.append(input)

    input.dispatchEvent(new Event("invalid"))
    setUserInvalid(false)
    input.dispatchEvent(new Event("input", { bubbles: true }))

    expect(input.hasAttribute("aria-invalid")).toBe(false)
    expect(input.hasAttribute("data-kb-client-invalid")).toBe(false)
  })

  it("keeps server-rendered aria-invalid state untouched", () => {
    const { input } = makeInput({ userInvalid: false })
    input.setAttribute("aria-invalid", "true")
    document.body.append(input)

    input.dispatchEvent(new Event("input", { bubbles: true }))

    expect(input.getAttribute("aria-invalid")).toBe("true")
    expect(input.hasAttribute("data-kb-client-invalid")).toBe(false)
  })
})
