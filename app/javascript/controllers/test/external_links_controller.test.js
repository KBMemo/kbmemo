// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import ExternalLinksController from "../external_links_controller.js"

let application

beforeEach(() => {
  document.body.innerHTML = '<main data-controller="external-links"></main>'
  application = Application.start()
  application.register("external-links", ExternalLinksController)
})

afterEach(() => {
  application?.stop()
  document.body.replaceChildren()
})

describe("external-links", () => {
  it("opens external HTTP links in a new tab and preserves rel values", async () => {
    const main = document.querySelector("main")
    main.innerHTML = '<a href="https://example.com/page" rel="nofollow">External</a>'

    await vi.waitFor(() => {
      const link = main.querySelector("a")
      expect(link.target).toBe("_blank")
      expect(link.rel.split(/\s+/)).toEqual(expect.arrayContaining(["nofollow", "noopener"]))
    })
  })

  it("leaves same-origin, fragment, and non-HTTP links unchanged", async () => {
    const main = document.querySelector("main")
    main.innerHTML = `
      <a id="internal" href="/memos">Internal</a>
      <a id="fragment" href="#section">Fragment</a>
      <a id="email" href="mailto:user@example.com">Email</a>
    `

    await vi.waitFor(() => expect(main.querySelectorAll("a").length).toBe(3))
    for (const link of main.querySelectorAll("a")) {
      expect(link.getAttribute("target")).toBeNull()
      expect(link.getAttribute("rel")).toBeNull()
    }
  })

  it("handles links added after the controller connects", async () => {
    const main = document.querySelector("main")
    const link = document.createElement("a")
    link.href = "https://outside.example/article"
    main.append(link)

    await vi.waitFor(() => expect(link.target).toBe("_blank"))
    expect(link.rel).toContain("noopener")
  })
})
