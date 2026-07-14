import { Controller } from "@hotwired/stimulus"
import { useDebounce } from "stimulus-use"

// サイドバー: タイトル・本文検索。
// 入力のたびに全ページ遷移するとフォーカスと未確定入力が失われるため、
// 一覧コンテナだけ fetch 置換する。
export default class extends Controller {
  static debounces = ["queueSearch"]
  static targets = ["input", "form", "clear"]
  static values = {
    debounce: { type: Number, default: 400 },
    listUrl: { type: String, default: "/memos/sidebar_memo_list" }
  }

  connect() {
    useDebounce(this, { wait: this.debounceValue })
    this.abortController = null
  }

  disconnect() {
    this.abortController?.abort()
  }

  queueSearch() {
    this.refreshResults(this.currentQuery())
  }

  submitSearch(event) {
    event.preventDefault()
    this.refreshResults(this.currentQuery())
  }

  clear(event) {
    event.preventDefault()
    if (!this.hasInputTarget) return
    this.inputTarget.value = ""
    this.refreshResults("")
    this.inputTarget.focus()
  }

  currentQuery() {
    return this.hasInputTarget ? this.inputTarget.value.trim() : ""
  }

  async refreshResults(query) {
    this.syncClearButton(query)
    this.syncHeading(query)
    this.replaceUrl(query)

    this.abortController?.abort()
    this.abortController = new AbortController()
    const { signal } = this.abortController

    const list = document.getElementById("memo_sidebar_memo_list_container")
    list?.setAttribute("aria-busy", "true")

    let response
    try {
      response = await fetch(`${this.listUrlValue}?${this.listParams(query)}`, {
        headers: { Accept: "text/html", "X-Kbmemo-Sidebar-Sync": "1" },
        credentials: "same-origin",
        cache: "no-store",
        signal
      })
    } catch (error) {
      if (error.name === "AbortError") return
      list?.removeAttribute("aria-busy")
      throw error
    }

    if (!response.ok) {
      list?.removeAttribute("aria-busy")
      return
    }

    const html = await response.text()
    if (signal.aborted) return

    const doc = new DOMParser().parseFromString(html, "text/html")
    const newContainer = doc.getElementById("memo_sidebar_memo_list_container")
    const currentContainer = document.getElementById("memo_sidebar_memo_list_container")
    if (!newContainer || !currentContainer) return

    currentContainer.replaceWith(document.importNode(newContainer, true))
    document.dispatchEvent(new Event("turbo:render"))
  }

  listParams(query) {
    const params = new URLSearchParams({ sidebar_view: "search" })
    if (query) params.set("q", query)
    return params
  }

  syncClearButton(query) {
    if (!this.hasClearTarget) return
    this.clearTarget.classList.toggle("hidden", query === "")
  }

  syncHeading(query) {
    const heading = document.getElementById("memo_sidebar_list_heading")
    if (!heading) return

    if (query) {
      heading.replaceChildren(
        document.createTextNode("検索結果"),
        Object.assign(document.createElement("span"), {
          className: "ml-1 font-normal normal-case kb-text-subtle",
          textContent: `「${query}」`
        })
      )
    } else {
      heading.textContent = "メモ一覧"
    }
  }

  replaceUrl(query) {
    const url = new URL(window.location.href)
    url.searchParams.set("sidebar_view", "search")
    if (query) {
      url.searchParams.set("q", query)
    } else {
      url.searchParams.delete("q")
    }
    window.history.replaceState(window.history.state, "", url.toString())
  }
}
