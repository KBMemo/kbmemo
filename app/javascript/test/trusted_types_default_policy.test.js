import { afterEach, describe, expect, it, vi } from "vitest"

describe("trusted_types_default_policy", () => {
  afterEach(() => {
    vi.resetModules()
    vi.unstubAllGlobals()
  })

  it("installs a default Trusted Types policy for framework sinks", async () => {
    const createPolicy = vi.fn((_name, rules) => rules)
    vi.stubGlobal("trustedTypes", { createPolicy })

    await import("../trusted_types_default_policy.js")

    expect(createPolicy).toHaveBeenCalledWith("default", expect.any(Object))
    expect(createPolicy.mock.calls[0][1].createHTML("<turbo-stream></turbo-stream>")).toBe(
      "<turbo-stream></turbo-stream>"
    )
    expect(createPolicy.mock.calls[0][1].createScript("console.log('turbo')")).toBe(
      "console.log('turbo')"
    )
  })

  it("ignores duplicate default policy registration", async () => {
    vi.stubGlobal("trustedTypes", {
      createPolicy: () => {
        throw new TypeError("Policy already exists")
      },
    })

    const mod = await import("../trusted_types_default_policy.js")

    expect(mod.installDefaultTrustedTypesPolicy()).toBeNull()
  })
})
