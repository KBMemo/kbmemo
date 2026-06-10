import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "results", "panel", "memoId", "submit"]
  static values = {
    searchUrl: String,
    debounce: { type: Number, default: 200 }
  }

  connect() {
    this._activeIndex = -1
    this._items = []
    this._pointerDown = false
    this.search()
  }

  queryInput() {
    if (this.hasMemoIdTarget) {
      this.memoIdTarget.value = ""
    }
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = true
    }
    this.search()
  }

  open() {
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("hidden")
    }
    if (this.hasQueryTarget) {
      this.queryTarget.setAttribute("aria-expanded", "true")
    }
    this.search()
  }

  closeLater() {
    setTimeout(() => {
      if (this._pointerDown) return
      this.close()
    }, 150)
  }

  close() {
    if (this.hasPanelTarget) {
      this.panelTarget.classList.add("hidden")
    }
    if (this.hasQueryTarget) {
      this.queryTarget.setAttribute("aria-expanded", "false")
    }
    this._activeIndex = -1
  }

  pointerDown() {
    this._pointerDown = true
  }

  pointerUp() {
    this._pointerDown = false
  }

  keydown(event) {
    const panelOpen = this.hasPanelTarget && !this.panelTarget.classList.contains("hidden")

    if (!panelOpen) {
      if (event.key === "ArrowDown") {
        event.preventDefault()
        this.open()
      }
      return
    }

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this._moveActive(1)
      return
    }

    if (event.key === "ArrowUp") {
      event.preventDefault()
      this._moveActive(-1)
      return
    }

    if (event.key === "Enter" && this._activeIndex >= 0) {
      event.preventDefault()
      this._selectIndex(this._activeIndex)
    }
  }

  select(event) {
    const button = event.currentTarget
    const id = button.dataset.memoId
    const title = button.dataset.memoTitle
    if (!id || !title) return

    this._applySelection(id, title)
    this.close()
  }

  submitForm(event) {
    if (!this.hasMemoIdTarget || !this.memoIdTarget.value) {
      event.preventDefault()
    }
  }

  search() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fetchResults(), this.debounceValue)
  }

  async _fetchResults() {
    const q = this.queryTarget?.value?.trim() || ""
    const url = new URL(this.searchUrlValue, window.location.origin)
    if (q) url.searchParams.set("q", q)

    try {
      const res = await fetch(url.toString(), {
        headers: { Accept: "application/json" }
      })
      if (!res.ok) return
      const items = await res.json()
      this._renderResults(items)
    } catch (e) {
      console.error(e)
    }
  }

  _renderResults(items) {
    if (!this.hasResultsTarget) return

    this._items = items
    this._activeIndex = items.length ? 0 : -1

    if (!items.length) {
      this.resultsTarget.innerHTML =
        '<p class="px-3 py-2 text-sm kb-text-muted">該当するメモがありません</p>'
      return
    }

    this.resultsTarget.innerHTML = items
      .map((item, index) => {
        const tags = (item.tags || []).slice(0, 3).join(", ")
        const tagLine = tags ? `<span class="kb-text-subtle"> · ${this._escape(tags)}</span>` : ""
        return `<button type="button" role="option" class="block w-full border-b kb-border px-3 py-2 text-left text-sm kb-hover-row" data-action="memo-search-picker#select" data-memo-id="${item.id}" data-memo-title="${this._escapeAttr(item.title)}" data-index="${index}">
          <span class="font-medium kb-text-primary">${this._escape(item.title)}</span>${tagLine}
        </button>`
      })
      .join("")

    this._highlightActive()
  }

  _moveActive(delta) {
    if (!this._items.length) return
    this._activeIndex = Math.max(0, Math.min(this._items.length - 1, this._activeIndex + delta))
    this._highlightActive()
  }

  _selectIndex(index) {
    const item = this._items[index]
    if (!item) return
    this._applySelection(String(item.id), item.title)
    this.close()
  }

  _applySelection(id, title) {
    if (this.hasMemoIdTarget) {
      this.memoIdTarget.value = id
    }
    if (this.hasQueryTarget) {
      this.queryTarget.value = title
    }
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = false
    }
  }

  _highlightActive() {
    if (!this.hasResultsTarget) return
    const buttons = this.resultsTarget.querySelectorAll("button[data-index]")
    buttons.forEach((button, index) => {
      button.classList.toggle("kb-selected-row", index === this._activeIndex)
      button.setAttribute("aria-selected", index === this._activeIndex ? "true" : "false")
    })
    buttons[this._activeIndex]?.scrollIntoView({ block: "nearest" })
  }

  _escape(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }

  _escapeAttr(text) {
    return this._escape(text).replace(/'/g, "&#39;")
  }
}
