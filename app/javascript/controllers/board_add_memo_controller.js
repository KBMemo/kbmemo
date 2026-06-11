import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["results", "query", "panel"]
  static values = {
    searchUrl: String,
    createUrl: String,
    defaultColumnId: String
  }

  connect() {
    this._opener = null
  }

  open() {
    if (!this.hasPanelTarget) return
    this._opener = document.activeElement instanceof HTMLElement ? document.activeElement : null
    if (typeof this.panelTarget.showModal === "function") {
      if (!this.panelTarget.open) this.panelTarget.showModal()
    } else {
      this.panelTarget.setAttribute("open", "")
    }
    requestAnimationFrame(() => this.queryTarget?.focus())
    this.search()
  }

  close() {
    if (!this.hasPanelTarget) return
    if (typeof this.panelTarget.close === "function" && this.panelTarget.open) {
      this.panelTarget.close()
    } else {
      this.panelTarget.removeAttribute("open")
    }
    this._opener?.focus()
    this._opener = null
  }

  backdropClick(event) {
    if (event.target === this.panelTarget) this.close()
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
      const empty = document.createElement("p")
      empty.className = "px-3 py-2 text-sm kb-text-muted"
      empty.textContent = "該当するメモがありません"
      this.resultsTarget.replaceChildren(empty)
      return
    }

    this.resultsTarget.replaceChildren(...items.map((item) => this._buildResultButton(item)))
  }

  _buildResultButton(item) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "block w-full border-b kb-border px-3 py-2 text-left text-sm kb-hover-row"
    button.setAttribute("data-action", "board-add-memo#add")
    button.dataset.memoId = String(item.id)

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

}
