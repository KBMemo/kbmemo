import { Controller } from "@hotwired/stimulus"

// カンバン列間・列内 DnD → PATCH move_card + Turbo Stream
export default class extends Controller {
  static targets = ["column", "card"]
  static values = { moveUrl: String }

  cardDragStart(event) {
    const card = event.currentTarget.closest("[data-memo-id]")
    if (!card) return

    this._dragMemoId = card.dataset.memoId
    this._dragSourceColumnId = card.dataset.columnId
    document.documentElement.classList.add("board-kanban-dnd-dragging")
    event.dataTransfer.setData("application/x-board-memo-id", this._dragMemoId)
    event.dataTransfer.effectAllowed = "move"
    card.classList.add("opacity-50")
  }

  cardDragEnd(event) {
    const card = event.currentTarget.closest("[data-memo-id]")
    card?.classList.remove("opacity-50")
    this._clearHighlights()
    this._dragMemoId = null
    this._dragSourceColumnId = null
    document.documentElement.classList.remove("board-kanban-dnd-dragging")
  }

  prepareDrag(event) {
    const card = event.currentTarget.closest("[data-memo-id]")
    if (card) card.draggable = true
  }

  allowDrop(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dragEnterColumn(event) {
    event.preventDefault()
    const zone = event.currentTarget.closest("[data-drop-column]")
    if (!zone || !this._dragMemoId) return
    zone.classList.add("ring-2", "ring-blue-500", "bg-blue-50/80")
  }

  dragLeaveColumn(event) {
    const zone = event.currentTarget.closest("[data-drop-column]")
    if (!zone) return
    const rt = event.relatedTarget
    if (rt && zone.contains(rt)) return
    zone.classList.remove("ring-2", "ring-blue-500", "bg-blue-50/80")
  }

  async dropOnColumn(event) {
    event.preventDefault()
    event.stopPropagation()
    this._clearHighlights()

    const memoId = event.dataTransfer.getData("application/x-board-memo-id") || this._dragMemoId
    if (!memoId) return

    const zone = event.currentTarget.closest("[data-drop-column]")
    const columnId = zone?.dataset.columnId
    if (!columnId) return

    const cardEl = event.target.closest("[data-memo-id]")
    let position
    if (cardEl && cardEl.dataset.columnId === columnId) {
      position = Number(cardEl.dataset.position) || 0
    } else {
      position = zone.querySelectorAll("[data-memo-id]").length
    }

    await this._patchMove(memoId, columnId, position)
  }

  async _patchMove(memoId, columnId, position) {
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    try {
      const res = await fetch(this.moveUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html, application/json"
        },
        body: JSON.stringify({
          memo_id: Number(memoId),
          kanban_column_id: Number(columnId),
          kanban_position: position
        })
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
    }
  }

  disconnect() {
    document.documentElement.classList.remove("board-kanban-dnd-dragging")
  }

  _clearHighlights() {
    this.element.querySelectorAll("[data-drop-column]").forEach((el) => {
      el.classList.remove("ring-2", "ring-blue-500", "bg-blue-50/80")
    })
  }
}
