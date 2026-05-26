import { Controller } from "@hotwired/stimulus"

// ノートブック左ペインのメモツリー DnD（順序・階層）
export default class extends Controller {
  static values = { reorderUrl: String }

  entryDragStart(event) {
    const row = event.currentTarget.closest("[data-notebook-memo-id]")
    if (!row) return

    this._dragEntryId = row.dataset.notebookMemoId
    document.documentElement.classList.add("notebook-memo-tree-dragging")
    event.dataTransfer.setData("application/x-notebook-memo-id", this._dragEntryId)
    event.dataTransfer.effectAllowed = "move"
    row.classList.add("opacity-50")
  }

  entryDragEnd(event) {
    const row = event.currentTarget.closest("[data-notebook-memo-id]")
    row?.classList.remove("opacity-50")
    this._clearHighlights()
    this._dragEntryId = null
    document.documentElement.classList.remove("notebook-memo-tree-dragging")
  }

  prepareDrag(event) {
    const row = event.currentTarget.closest("[data-notebook-memo-id]")
    if (row) row.draggable = true
  }

  allowDrop(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dragEnterRow(event) {
    event.preventDefault()
    if (!this._dragEntryId) return
    const row = event.currentTarget.closest("[data-notebook-memo-row]")
    if (!row || row.dataset.notebookMemoId === this._dragEntryId) return
    row.classList.add("ring-2", "ring-blue-500", "bg-blue-50/80")
  }

  dragLeaveRow(event) {
    const row = event.currentTarget.closest("[data-notebook-memo-row]")
    if (!row) return
    const rt = event.relatedTarget
    if (rt && row.contains(rt)) return
    row.classList.remove("ring-2", "ring-blue-500", "bg-blue-50/80")
  }

  async dropOnRow(event) {
    event.preventDefault()
    event.stopPropagation()
    this._clearHighlights()

    const entryId = event.dataTransfer.getData("application/x-notebook-memo-id") || this._dragEntryId
    if (!entryId) return

    const row = event.currentTarget.closest("[data-notebook-memo-row]")
    if (!row || row.dataset.notebookMemoId === entryId) return

    const rect = row.getBoundingClientRect()
    const y = event.clientY - rect.top
    const third = Math.max(rect.height / 3, 1)

    let parentId
    let position

    if (y < third) {
      parentId = row.dataset.parentId || null
      position = Number(row.dataset.position) || 0
    } else if (y > third * 2) {
      parentId = row.dataset.parentId || null
      position = (Number(row.dataset.position) || 0) + 1
    } else {
      parentId = row.dataset.notebookMemoId
      const childList = row.querySelector("[data-tree-children]")
      position = childList ? childList.querySelectorAll(":scope > li[data-notebook-memo-id]").length : 0
    }

    await this._patchMove(entryId, parentId, position)
  }

  async dropOnRoot(event) {
    event.preventDefault()
    event.stopPropagation()
    this._clearHighlights()

    const entryId = event.dataTransfer.getData("application/x-notebook-memo-id") || this._dragEntryId
    if (!entryId) return

    const zone = event.currentTarget
    const position = zone.querySelectorAll(":scope > li[data-notebook-memo-id]").length
    await this._patchMove(entryId, null, position)
  }

  async dropOnChildren(event) {
    event.preventDefault()
    event.stopPropagation()
    this._clearHighlights()

    const entryId = event.dataTransfer.getData("application/x-notebook-memo-id") || this._dragEntryId
    if (!entryId) return

    const list = event.currentTarget
    const parentLi = list.closest("li[data-notebook-memo-id]")
    if (!parentLi || parentLi.dataset.notebookMemoId === entryId) return

    const position = list.querySelectorAll(":scope > li[data-notebook-memo-id]").length
    await this._patchMove(entryId, parentLi.dataset.notebookMemoId, position)
  }

  async _patchMove(entryId, parentId, position) {
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    const body = {
      notebook_memo_id: Number(entryId),
      position
    }
    if (parentId) body.parent_id = Number(parentId)

    try {
      const res = await fetch(this.reorderUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html, application/json"
        },
        body: JSON.stringify(body)
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
      this._dragEntryId = null
      document.documentElement.classList.remove("notebook-memo-tree-dragging")
    }
  }

  disconnect() {
    document.documentElement.classList.remove("notebook-memo-tree-dragging")
  }

  _clearHighlights() {
    this.element.querySelectorAll("[data-notebook-memo-row]").forEach((el) => {
      el.classList.remove("ring-2", "ring-blue-500", "bg-blue-50/80")
    })
  }
}
