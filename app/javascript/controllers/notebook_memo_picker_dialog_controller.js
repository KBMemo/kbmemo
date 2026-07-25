import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "parentId", "query", "results", "memoId", "submit"]
  static values = {
    searchUrl: String,
    debounce: { type: Number, default: 200 }
  }

  connect() {
    this._opener = null
  }

  disconnect() {
    clearTimeout(this._timer)
    this._abortController?.abort()
  }

  open(event) {
    if (!this.hasDialogTarget) return

    this._opener = event.currentTarget
    const form = this.dialogTarget.querySelector("form")
    form?.reset()
    this.parentIdTarget.value = event.params.parentId || ""
    this.memoIdTarget.value = ""
    this.submitTarget.disabled = true

    if (typeof this.dialogTarget.showModal === "function") {
      if (!this.dialogTarget.open) this.dialogTarget.showModal()
    } else {
      this.dialogTarget.setAttribute("open", "")
    }

    requestAnimationFrame(() => {
      this.queryTarget.focus()
      this.search()
    })
  }

  close() {
    if (!this.hasDialogTarget) return

    if (typeof this.dialogTarget.close === "function" && this.dialogTarget.open) {
      this.dialogTarget.close()
    } else {
      this.dialogTarget.removeAttribute("open")
      this.restoreFocus()
    }
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  restoreFocus() {
    this._opener?.focus()
    this._opener = null
  }

  queryInput() {
    this.memoIdTarget.value = ""
    this.submitTarget.disabled = true
    this.search()
  }

  submit(event) {
    if (!this.memoIdTarget.value) event.preventDefault()
  }

  search() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.fetchResults(), this.debounceValue)
  }

  async fetchResults() {
    this._abortController?.abort()
    this._abortController = new AbortController()
    const url = new URL(this.searchUrlValue, window.location.origin)
    const query = this.queryTarget.value.trim()
    if (query) url.searchParams.set("q", query)

    try {
      const response = await fetch(url.toString(), {
        headers: { Accept: "application/json" },
        signal: this._abortController.signal
      })
      if (!response.ok) return
      this.renderResults(await response.json())
    } catch (error) {
      if (error.name === "AbortError") return
      console.error(error)
    }
  }

  renderResults(items) {
    if (!items.length) {
      const empty = document.createElement("p")
      empty.className = "px-3 py-2 text-sm kb-text-muted"
      empty.textContent = "該当するメモがありません"
      this.resultsTarget.replaceChildren(empty)
      return
    }

    this.resultsTarget.replaceChildren(...items.map((item) => this.buildResultButton(item)))
  }

  buildResultButton(item) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "block w-full border-b kb-border px-3 py-2 text-left text-sm kb-hover-row"
    button.dataset.action = "notebook-memo-picker-dialog#select"
    button.dataset.memoId = String(item.id)
    button.dataset.memoTitle = String(item.title || "")

    const title = document.createElement("span")
    title.className = "font-medium kb-text-primary"
    title.textContent = String(item.title || "")
    button.append(title)

    const tags = (item.tags || []).slice(0, 3).join(", ")
    if (tags) {
      const tagLine = document.createElement("span")
      tagLine.className = "kb-text-subtle"
      tagLine.textContent = ` · ${tags}`
      button.append(tagLine)
    }

    return button
  }

  select(event) {
    this.memoIdTarget.value = event.currentTarget.dataset.memoId || ""
    this.queryTarget.value = event.currentTarget.dataset.memoTitle || ""
    this.submitTarget.disabled = !this.memoIdTarget.value
  }
}
