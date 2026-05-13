import { Controller } from "@hotwired/stimulus"

// メモ一覧のドラッグハンドルからディレクトリ行へドロップし、draft PATCH で所属を変更する
export default class extends Controller {
  memoDragStart(event) {
    const el = event.currentTarget
    const url = el.dataset.draftUrl
    if (!url) return
    this._dragActive = true
    document.documentElement.classList.add("memo-directory-dnd-dragging")
    this._dragDraftUrl = url
    this._dragSourceDirectoryId = el.dataset.memoDirectoryId ? String(el.dataset.memoDirectoryId) : ""
    event.dataTransfer.setData("application/x-memo-draft-url", url)
    event.dataTransfer.effectAllowed = "move"
    el.classList.add("opacity-50")
  }

  memoDragEnd(event) {
    event.currentTarget.classList.remove("opacity-50")
    this._clearBodyDragCursor()
    this._clearDropHighlights()
    this._dragDraftUrl = null
    this._dragSourceDirectoryId = null
  }

  _clearBodyDragCursor() {
    if (!this._dragActive) return
    document.documentElement.classList.remove("memo-directory-dnd-dragging")
    this._dragActive = false
  }

  allowDrop(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dragEnterDirectory(event) {
    event.preventDefault()
    if (!this._dragDraftUrl) return
    const el = event.currentTarget
    const targetId = el.dataset.memoDirectoryId ? String(el.dataset.memoDirectoryId) : ""
    if (!targetId || targetId === this._dragSourceDirectoryId) return
    el.classList.add("ring-2", "ring-blue-500", "bg-blue-50/80")
  }

  dragLeaveDirectory(event) {
    const el = event.currentTarget
    const rt = event.relatedTarget
    if (rt && el.contains(rt)) return
    el.classList.remove("ring-2", "ring-blue-500", "bg-blue-50/80")
  }

  async dropOnDirectory(event) {
    event.preventDefault()
    event.stopPropagation()
    this._clearDropHighlights()

    const url =
      event.dataTransfer.getData("application/x-memo-draft-url") || this._dragDraftUrl
    const el = event.currentTarget
    const targetId = el.dataset.memoDirectoryId ? String(el.dataset.memoDirectoryId) : ""
    if (!url || !targetId) return
    if (targetId === this._dragSourceDirectoryId) return

    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    try {
      const res = await fetch(url, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html, application/json"
        },
        body: JSON.stringify({ memo: { memo_directory_id: Number(targetId) } })
      })
      if (!res.ok) return
      const ct = (res.headers.get("Content-Type") || "").toLowerCase()
      if (ct.includes("vnd.turbo-stream")) {
        const stream = await res.text()
        if (window.Turbo?.renderStreamMessage) {
          window.Turbo.renderStreamMessage(stream)
        }
      }
    } catch (e) {
      console.error(e)
    } finally {
      this._dragDraftUrl = null
      this._dragSourceDirectoryId = null
      this._clearBodyDragCursor()
    }
  }

  disconnect() {
    this._clearBodyDragCursor()
  }

  _clearDropHighlights() {
    this.element.querySelectorAll("[data-drop-directory]").forEach((el) => {
      el.classList.remove("ring-2", "ring-blue-500", "bg-blue-50/80")
    })
  }
}
