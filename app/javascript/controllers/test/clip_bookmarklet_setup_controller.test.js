// @vitest-environment happy-dom

import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import ClipBookmarkletSetupController from "../clip_bookmarklet_setup_controller.js"

const TOKEN = "kbmemo_clip_reusable_token"
const API_TEMPLATE =
  "void function(base, token) { window.clip = [base, token] }(__KBMEMO_BASE__, __KBMEMO_TOKEN__)"
const CLIPBOARD_TEMPLATE = "void navigator.clipboard.writeText(document.title)"

let application

function response(body) {
  return Promise.resolve({ ok: true, text: () => Promise.resolve(body) })
}

async function mount({ revealedToken = "" } = {}) {
  document.body.innerHTML = `
    <section
      data-controller="clip-bookmarklet-setup"
      data-clip-bookmarklet-setup-default-base-url-value="https://kbmemo.example.com"
      data-clip-bookmarklet-setup-revealed-token-value="${revealedToken}"
      data-clip-bookmarklet-setup-token-configured-value="true"
    >
      <p class="hidden" data-clip-bookmarklet-setup-target="statusMessage"></p>
      <a
        href="#"
        class="opacity-50 pointer-events-none"
        aria-disabled="true"
        data-prefilled="false"
        data-clip-bookmarklet-setup-target="apiBookmarkletLink"
      >kbmemo に保存</a>
      <a
        href="#"
        data-clip-bookmarklet-setup-target="clipboardBookmarkletLink"
      >kbmemo にコピー</a>
    </section>
  `

  await vi.waitFor(() => {
    const link = document.querySelector(
      "[data-clip-bookmarklet-setup-target='apiBookmarkletLink']"
    )
    expect(link.getAttribute("aria-disabled")).toBeNull()
  })
}

beforeEach(() => {
  document.body.replaceChildren()
  localStorage.clear()
  vi.stubGlobal("fetch", vi.fn((url) => {
    if (url.toString().includes("kbmemo_clip_api")) return response(API_TEMPLATE)
    return response(CLIPBOARD_TEMPLATE)
  }))
  application = Application.start()
  application.register("clip-bookmarklet-setup", ClipBookmarkletSetupController)
})

afterEach(() => {
  application?.stop()
  vi.unstubAllGlobals()
})

describe("clip-bookmarklet-setup", () => {
  it("stores a newly revealed token in the browser", async () => {
    await mount({ revealedToken: TOKEN })

    expect(localStorage.getItem("kbmemo_web_clip_token")).toBe(TOKEN)
  })

  it("rebuilds the bookmarklet with the same stored token on a later visit", async () => {
    localStorage.setItem("kbmemo_web_clip_token", TOKEN)
    await mount()

    const link = document.querySelector(
      "[data-clip-bookmarklet-setup-target='apiBookmarkletLink']"
    )
    const code = decodeURIComponent(link.href.replace(/^javascript:/, ""))

    expect(code).toContain(JSON.stringify(TOKEN))
    expect(link.classList.contains("pointer-events-none")).toBe(false)
  })
})
