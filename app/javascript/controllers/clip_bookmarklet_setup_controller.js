import { Controller } from "@hotwired/stimulus"

const STORAGE_BASE = "kbmemo_clip_base_url"
const STORAGE_TOKEN = "kbmemo_web_clip_token"
const LEGACY_STORAGE_TOKEN = "kbmemo_clip_api_token"
const TOKEN_RE = /^kbmemo_clip_[A-Za-z0-9_-]+$/

// プロフィール: 発行直後のトークン埋め込み、または localStorage のトークンで API ブックマークレットを有効化。
export default class extends Controller {
  static targets = ["apiBookmarkletLink", "clipboardBookmarkletLink", "statusMessage", "activeTokenMessage"]

  static values = {
    defaultBaseUrl: String,
    revealedToken: String,
    tokenConfigured: Boolean,
    tokenLabels: { type: Object, default: {} },
    apiTemplateUrl: { type: String, default: "/bookmarklets/kbmemo_clip_api.bookmarklet.js" },
    clipboardTemplateUrl: { type: String, default: "/bookmarklets/kbmemo_clip.bookmarklet.js" }
  }

  connect() {
    this._apiTemplate = null
    this._clipboardCode = null

    const revealed = this.revealedTokenValue?.trim()
    if (revealed) {
      localStorage.setItem(STORAGE_TOKEN, revealed)
      localStorage.removeItem(LEGACY_STORAGE_TOKEN)
    }

    const baseUrl = this.resolveBaseUrl()
    if (baseUrl) {
      localStorage.setItem(STORAGE_BASE, baseUrl)
    }

    void this.loadTemplates()
  }

  async loadTemplates() {
    try {
      const [apiRes, clipRes] = await Promise.all([
        fetch(this.apiTemplateUrlValue),
        fetch(this.clipboardTemplateUrlValue)
      ])
      if (!apiRes.ok || !clipRes.ok) throw new Error("template fetch failed")

      this._apiTemplate = (await apiRes.text()).trim()
      this._clipboardCode = (await clipRes.text()).trim()

      if (
        !this._apiTemplate.includes("__KBMEMO_BASE__") ||
        !this._apiTemplate.includes("__KBMEMO_TOKEN__")
      ) {
        throw new Error("invalid api template")
      }

      this.enableClipboardBookmarklet()
      this.enableApiBookmarkletFromStorage()
    } catch {
      this.setStatus(
        "ブックマークレットを読み込めませんでした。ページを再読み込みしてください。"
      )
    }
  }

  enableApiBookmarkletFromStorage() {
    if (!this.hasApiBookmarkletLinkTarget || !this._apiTemplate) return

    const link = this.apiBookmarkletLinkTarget
    if (link.getAttribute("data-prefilled") === "true") {
      return
    }

    const baseUrl = this.resolveBaseUrl()
    const token = this.resolveToken()
    const tokenMessage = this.validateToken(token)

    if (!baseUrl || tokenMessage) {
      this.setActiveTokenMessage("")
      this.disableApiBookmarklet(tokenMessage || this.missingTokenMessage())
      return
    }

    link.href = this.buildApiBookmarklet(this._apiTemplate, baseUrl, token)
    this.markApiBookmarkletReady()
    this.setActiveTokenMessage(this.activeTokenMessage(token))
    this.setStatus("")
  }

  enableClipboardBookmarklet() {
    if (!this.hasClipboardBookmarkletLinkTarget || !this._clipboardCode) return

    const link = this.clipboardBookmarkletLinkTarget
    link.href = `javascript:${encodeURIComponent(this._clipboardCode)}`
    link.classList.remove("opacity-50", "pointer-events-none")
    link.removeAttribute("aria-disabled")
  }

  markApiBookmarkletReady() {
    const link = this.apiBookmarkletLinkTarget
    link.classList.remove("opacity-50", "pointer-events-none")
    link.removeAttribute("aria-disabled")
    link.title = ""
  }

  disableApiBookmarklet(message) {
    const link = this.apiBookmarkletLinkTarget
    if (link.getAttribute("data-prefilled") === "true") return

    link.href = "#"
    link.classList.add("opacity-50", "pointer-events-none")
    link.setAttribute("aria-disabled", "true")
    link.title = message
    this.setStatus(message)
  }

  resolveBaseUrl() {
    const fromValue = this.normalizeBase(this.defaultBaseUrlValue)
    if (fromValue) return fromValue

    const stored = localStorage.getItem(STORAGE_BASE)
    if (stored) return this.normalizeBase(stored)

    return this.normalizeBase(window.location.origin)
  }

  resolveToken() {
    const revealed = this.revealedTokenValue?.trim()
    if (revealed) return revealed

    return localStorage.getItem(STORAGE_TOKEN)?.trim() || ""
  }

  missingTokenMessage() {
    if (this.tokenConfiguredValue) {
      return "別のブラウザで使う場合は、上の「トークンを発行」で再発行してからブックマークレットを取り直してください。"
    }
    return "まず上の「トークンを発行」を押してください。"
  }

  setStatus(message) {
    if (!this.hasStatusMessageTarget) return
    this.statusMessageTarget.textContent = message
    this.statusMessageTarget.classList.toggle("hidden", !message)
  }

  setActiveTokenMessage(message) {
    if (!this.hasActiveTokenMessageTarget) return
    this.activeTokenMessageTarget.textContent = message
    this.activeTokenMessageTarget.classList.toggle("hidden", !message)
  }

  activeTokenMessage(token) {
    const prefix = token.slice(0, 16)
    const name = this.tokenLabelsValue[prefix]
    const label = name ? `「${name}」` : "名称不明"

    return `このブラウザで使用中: ${label}（先頭: ${prefix}）`
  }

  normalizeBase(value) {
    const stripped = (value || "")
      .trim()
      .replace(/^["']+|["']+$/g, "")
      .replace(/\/$/, "")
    if (!stripped) return ""

    try {
      return new URL(stripped).origin
    } catch {
      return ""
    }
  }

  validateToken(token) {
    if (!token) return this.missingTokenMessage()
    if (!TOKEN_RE.test(token)) {
      return "トークンを再発行してブックマークレットを取り直してください。"
    }
    return ""
  }

  buildApiBookmarklet(template, baseUrl, token) {
    const code = template
      .replace("__KBMEMO_BASE__", JSON.stringify(baseUrl))
      .replace("__KBMEMO_TOKEN__", JSON.stringify(token))
    return `javascript:${encodeURIComponent(code)}`
  }
}
