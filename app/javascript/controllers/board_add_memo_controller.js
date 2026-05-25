import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["results", "query", "panel"]
  static values = {
    searchUrl: String,
    createUrl: String,
    defaultColumnId: String
  }

  open() {
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.remove("hidden")
    this.queryTarget?.focus()
    this.search()
  }

  close() {
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.add("hidden")
  }

  search() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fetchResults(), 200)
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
    if (!items.length) {
      this.resultsTarget.innerHTML = '<p class="px-3 py-2 text-sm kb-text-muted">該当するメモがありません</p>'
      return
    }

    this.resultsTarget.innerHTML = items
      .map((item) => {
        const tags = (item.tags || []).slice(0, 3).join(", ")
        const tagLine = tags ? `<span class="kb-text-subtle"> · ${this._escape(tags)}</span>` : ""
        return `<button type="button" class="block w-full border-b kb-border px-3 py-2 text-left text-sm kb-hover-row" data-action="board-add-memo#add" data-memo-id="${item.id}">
          <span class="font-medium kb-text-primary">${this._escape(item.title)}</span>${tagLine}
        </button>`
      })
      .join("")
  }

  async add(event) {
    const memoId = event.currentTarget.dataset.memoId
    if (!memoId) return

    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    const body = new FormData()
    body.append("memo_id", memoId)
    if (this.defaultColumnIdValue) {
      body.append("kanban_column_id", this.defaultColumnIdValue)
    }

    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": token,
          Accept: "text/vnd.turbo-stream.html"
        },
        body
      })
      if (!res.ok) return
      const stream = await res.text()
      if (window.Turbo?.renderStreamMessage) {
        window.Turbo.renderStreamMessage(stream)
      }
      this.close()
    } catch (e) {
      console.error(e)
    }
  }

  _escape(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
