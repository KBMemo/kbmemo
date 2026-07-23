import { Controller } from "@hotwired/stimulus"
import { jsonRequestHeaders, withAuthenticityToken } from "../lib/csrf_fetch.js"

export default class extends Controller {
  static targets = ["button", "panel", "title", "tags", "status"]
  static values = { url: String }

  connect() {
    this._abortController = null
    this._generating = false
    this._onBeforeVisit = (event) => this.beforeVisit(event)
    this._onBeforeCache = () => this.beforeCache()
    this._onBeforeUnload = (event) => this.beforeUnload(event)
    document.addEventListener("turbo:before-visit", this._onBeforeVisit)
    document.addEventListener("turbo:before-cache", this._onBeforeCache)
    window.addEventListener("beforeunload", this._onBeforeUnload)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this._onBeforeVisit)
    document.removeEventListener("turbo:before-cache", this._onBeforeCache)
    window.removeEventListener("beforeunload", this._onBeforeUnload)
    this.abortGeneration()
  }

  async generate() {
    if (!this.hasUrlValue || this.buttonTarget.disabled) return

    const requestController = new AbortController()
    this._abortController = requestController
    this._generating = true
    this.panelTarget.classList.add("hidden")
    this.setLoading(true)
    this.setStatus("提案を生成しています…")

    const draft = this.element.closest("[data-controller~='memo-draft']")
    draft?.querySelector("[data-controller~='memo-body-editor']")
      ?.dispatchEvent(new CustomEvent("kbmemo:flush-body-editor"))
    await Promise.resolve()

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: jsonRequestHeaders(),
        credentials: "same-origin",
        signal: requestController.signal,
        body: JSON.stringify(withAuthenticityToken({
          title: draft?.querySelector("[data-memo-draft-target='title']")?.value ?? "",
          body: draft?.querySelector("[data-memo-draft-target='body']")?.value ?? "",
          tags: this.currentTags(draft)
        }))
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "AIの提案を取得できませんでした。")

      this.renderSuggestion(data)
      this.setStatus("")
    } catch (error) {
      if (error.name === "AbortError") return
      this.panelTarget.classList.add("hidden")
      this.setStatus(error.message || "AIの提案を取得できませんでした。", true)
    } finally {
      if (this._abortController === requestController) {
        this._abortController = null
        this._generating = false
        this.setLoading(false)
      }
    }
  }

  beforeVisit(event) {
    if (!this._generating) return
    if (!window.confirm("AIの提案を生成中です。生成を中止してこのページを離れますか？")) {
      event.preventDefault()
      return
    }

    this.abortGeneration()
  }

  beforeCache() {
    this.abortGeneration()
  }

  beforeUnload(event) {
    if (!this._generating) return

    event.preventDefault()
    event.returnValue = ""
  }

  abortGeneration() {
    this._generating = false
    this._abortController?.abort()
    this._abortController = null
    if (!this.hasButtonTarget) return

    this.panelTarget.classList.add("hidden")
    this.setLoading(false)
    this.setStatus("")
  }

  apply() {
    const tags = Array.from(
      this.tagsTarget.querySelectorAll("input[type='checkbox']:checked")
    ).map((input) => input.value)

    this.dispatch("apply", {
      detail: { title: this.titleTarget.value.trim(), tags },
      bubbles: true
    })
    this.close()
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.setStatus("")
    this.buttonTarget.focus()
  }

  currentTags(draft) {
    const raw = draft?.querySelector("[data-memo-draft-target='tagList']")?.value ?? ""
    return raw.split(/[,，]/).map((tag) => tag.trim()).filter(Boolean)
  }

  renderSuggestion(data) {
    this.titleTarget.value = String(data.title || "")
    this.tagsTarget.replaceChildren()

    for (const [index, tag] of Array.from(data.tags || []).entries()) {
      const label = document.createElement("label")
      label.className = "inline-flex items-center gap-1.5 text-sm kb-text-primary"

      const checkbox = document.createElement("input")
      checkbox.type = "checkbox"
      checkbox.value = String(tag)
      checkbox.checked = true
      checkbox.id = `memo-ai-tag-${index}`

      const text = document.createElement("span")
      text.textContent = String(tag)

      label.append(checkbox, text)
      this.tagsTarget.appendChild(label)
    }

    this.panelTarget.classList.remove("hidden")
    this.titleTarget.focus()
  }

  setLoading(loading) {
    this.buttonTarget.disabled = loading
    this.buttonTarget.setAttribute("aria-busy", String(loading))
  }

  setStatus(message, error = false) {
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("hidden", !message)
    this.statusTarget.classList.toggle("kb-status-danger", error)
    this.statusTarget.classList.toggle("kb-text-muted", !error)
  }
}
