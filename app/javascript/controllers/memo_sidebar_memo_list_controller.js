import { Controller } from "@hotwired/stimulus"

// サイドバー メモ一覧: 初回は 15 件のみ表示し、下端が見えたら追加分を fetch する。
export default class extends Controller {
  static targets = ["sentinel", "sentinelLabel"]
  static values = {
    url: String,
    offset: Number,
    hasMore: Boolean,
    total: Number,
    scopeTotal: Number,
    params: Object
  }

  connect() {
    this.loading = false
    this.onScroll = () => this.checkScrollEnd()

    if (!this.hasMoreValue) {
      this.clearSentinel()
    } else {
      this.observeSentinel()
    }

    this.syncCount()
  }

  disconnect() {
    this.observer?.disconnect()
    this.observer = null
    this.scrollRootEl()?.removeEventListener("scroll", this.onScroll)
  }

  scrollRootEl() {
    return (
      document.getElementById("memo_sidebar_memo_list_scroll") ||
      this.element.closest("#memos_list_panel")
    )
  }

  observeSentinel() {
    if (!this.hasSentinelTarget) return

    this.observer?.disconnect()
    const root = this.scrollRootEl()
    const rootIsScrollable = root && root.scrollHeight > root.clientHeight

    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          void this.loadMore()
        }
      },
      {
        root: rootIsScrollable ? root : null,
        rootMargin: "240px 0px"
      }
    )
    this.observer.observe(this.sentinelTarget)

    if (rootIsScrollable) {
      root.removeEventListener("scroll", this.onScroll)
      root.addEventListener("scroll", this.onScroll, { passive: true })
    }
  }

  checkScrollEnd() {
    if (this.loading || !this.hasMoreValue || !this.hasSentinelTarget) return

    const root = this.scrollRootEl()
    if (!root) return

    const rootRect = root.getBoundingClientRect()
    const sentinelRect = this.sentinelTarget.getBoundingClientRect()
    if (sentinelRect.top <= rootRect.bottom + 240) {
      void this.loadMore()
    }
  }

  async loadMore() {
    if (this.loading || !this.hasMoreValue) return

    this.loading = true
    this.sentinelTarget?.setAttribute("aria-busy", "true")
    if (this.hasSentinelLabelTarget) this.sentinelLabelTarget.textContent = "読み込み中…"

    const params = new URLSearchParams({ append: "1", offset: String(this.offsetValue) })
    for (const [key, value] of Object.entries(this.paramsValue || {})) {
      if (value != null && value !== "") params.set(key, String(value))
    }

    try {
      const response = await fetch(`${this.urlValue}?${params}`, {
        headers: { Accept: "text/html", "X-Kbmemo-Sidebar-Sync": "1" },
        credentials: "same-origin",
        cache: "no-store"
      })
      if (!response.ok) return

      const html = await response.text()
      const doc = new DOMParser().parseFromString(html, "text/html")
      const meta = doc.getElementById("memo_sidebar_memo_list_append_meta")
      const list = this.element.querySelector("#memo_sidebar_memo_list")
      if (!list) return

      const rows = doc.querySelectorAll("li[id^='sidebar_row_memo_']")
      const sentinel = this.hasSentinelTarget ? this.sentinelTarget : null
      rows.forEach((row) => {
        list.insertBefore(document.importNode(row, true), sentinel)
      })

      if (meta) {
        this.offsetValue = Number(meta.dataset.nextOffset || this.offsetValue)
        this.hasMoreValue = meta.dataset.hasMore === "true"
      } else {
        this.hasMoreValue = false
      }

      if (this.reachedScopeEnd()) this.hasMoreValue = false

      if (!this.hasMoreValue) {
        this.clearSentinel()
      } else if (this.hasSentinelTarget) {
        this.observeSentinel()
      }

      this.syncCount()
      document.dispatchEvent(new Event("turbo:render"))
    } finally {
      this.loading = false
      this.sentinelTarget?.removeAttribute("aria-busy")
      if (this.hasSentinelLabelTarget) this.sentinelLabelTarget.textContent = ""
    }
  }

  syncCount() {
    const countEl = document.getElementById("memo_sidebar_list_count")
    const list = this.element.querySelector("#memo_sidebar_memo_list")
    if (!countEl || !list) return

    const shown = this.shownCount()
    const total = this.totalMemoCount()
    if (total <= 0) return

    countEl.textContent = `${shown} / ${total} 件`
  }

  shownCount() {
    const list = this.element.querySelector("#memo_sidebar_memo_list")
    if (!list) return 0
    return list.querySelectorAll("li[id^='sidebar_row_memo_']").length
  }

  totalMemoCount() {
    if (Number.isFinite(this.totalValue) && this.totalValue > 0) return this.totalValue

    const countEl = document.getElementById("memo_sidebar_list_count")
    const fromDom = Number(countEl?.dataset.totalCount)
    return Number.isFinite(fromDom) && fromDom > 0 ? fromDom : 0
  }

  scopeMemoCount() {
    if (Number.isFinite(this.scopeTotalValue) && this.scopeTotalValue > 0) return this.scopeTotalValue

    const countEl = document.getElementById("memo_sidebar_list_count")
    const fromDom = Number(countEl?.dataset.scopeTotalCount)
    return Number.isFinite(fromDom) && fromDom > 0 ? fromDom : 0
  }

  reachedScopeEnd() {
    const scopeTotal = this.scopeMemoCount()
    return scopeTotal > 0 && this.shownCount() >= scopeTotal
  }

  clearSentinel() {
    this.hasMoreValue = false
    this.sentinelTarget?.remove()
    this.observer?.disconnect()
    this.observer = null
    this.scrollRootEl()?.removeEventListener("scroll", this.onScroll)
  }
}
