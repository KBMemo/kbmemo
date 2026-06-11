import { Controller } from "@hotwired/stimulus"
import { setTrustedHTML } from "../trusted_html.js"
import {
  appendNavOpenDirectoryFields,
  loadOpenDirectoryIds,
  saveOpenDirectoryIds,
  syncOpenDirectoryIdsFromPanel
} from "../memo_directory_nav_open.js"

export default class extends Controller {
  static targets = ["dialog", "body"]
  static values = { newQuery: String }

  connect() {
    this._onCancel = (event) => {
      event.preventDefault()
      this.close()
    }
    this.dialogTarget.addEventListener("cancel", this._onCancel)
  }

  disconnect() {
    this.dialogTarget.removeEventListener("cancel", this._onCancel)
  }

  openNew(event) {
    event.preventDefault()
    event.stopPropagation()
    const parentId = event.params.parentId
    if (!parentId) return
    const params = new URLSearchParams({ dialog: "1", parent_id: parentId })
    if (this.hasNewQueryValue && this.newQueryValue) {
      new URLSearchParams(this.newQueryValue).forEach((value, key) => params.set(key, value))
    }
    void this.loadForm(`/memo_directories/new?${params.toString()}`)
  }

  openEdit(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = event.params.id
    if (!id) return
    void this.loadForm(`/memo_directories/${encodeURIComponent(id)}/edit?dialog=1`)
  }

  async deleteDirectory(event) {
    event.preventDefault()
    event.stopPropagation()

    const id = event.params.id
    const name = event.params.name || "このディレクトリ"
    if (!id) return
    if (!window.confirm(`「${name}」を削除しますか？`)) return

    syncOpenDirectoryIdsFromPanel()
    saveOpenDirectoryIds(loadOpenDirectoryIds().filter((openId) => openId !== String(id)))

    const params = new URLSearchParams()
    params.set("sidebar", "1")
    for (const openId of loadOpenDirectoryIds()) {
      params.append("nav_open_directory_ids[]", openId)
    }

    const pageUrl = new URL(window.location.href)
    const currentDirectoryId = pageUrl.searchParams.get("memo_directory_id")
    if (currentDirectoryId) {
      params.set("current_memo_directory_id", currentDirectoryId)
    }
    const memoMatch = pageUrl.pathname.match(/^\/memos\/(\d+)(?:\/edit)?$/)
    if (memoMatch) {
      params.set("open_memo_id", memoMatch[1])
    }

    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    const res = await fetch(`/memo_directories/${encodeURIComponent(id)}?${params.toString()}`, {
      method: "DELETE",
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": token || "",
        "X-Requested-With": "XMLHttpRequest"
      },
      credentials: "same-origin"
    })

    const stream = await res.text()
    if (stream.trim() && typeof window.Turbo?.renderStreamMessage === "function") {
      window.Turbo.renderStreamMessage(stream)
    }

    if (!res.ok) return

    const redirectUrl = res.headers.get("X-Sidebar-Redirect")
    if (redirectUrl && typeof window.Turbo?.visit === "function") {
      window.Turbo.visit(redirectUrl, { action: "replace" })
    }
  }

  async loadForm(url) {
    const res = await fetch(url, {
      headers: {
        Accept: "text/html",
        "X-Requested-With": "XMLHttpRequest"
      },
      credentials: "same-origin"
    })
    if (!res.ok) return

    this.replaceWithServerRenderedForm(await res.text())
    if (typeof this.dialogTarget.showModal === "function") {
      this.dialogTarget.showModal()
    }
    document.dispatchEvent(new Event("turbo:render"))
  }

  replaceWithServerRenderedForm(html) {
    // The memo directory dialog only loads same-origin server-rendered form fragments.
    setTrustedHTML(this.bodyTarget, "kbmemo-server-rendered-fragment", html)
  }

  submitStart(event) {
    syncOpenDirectoryIdsFromPanel()
    appendNavOpenDirectoryFields(event.target)
  }

  submitEnd(event) {
    if (event.detail.success) {
      this.close()
    }
  }

  cancel(event) {
    event.preventDefault()
    this.close()
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  close() {
    if (this.dialogTarget.open) {
      this.dialogTarget.close()
    }
    this.bodyTarget.replaceChildren()
  }
}
