import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    toggleUrl: String
  }

  async toggle(event) {
    const input = event.target
    if (!input?.matches?.('input[type="checkbox"][data-memo-checklist-id]')) return

    const id = input.dataset.memoChecklistId
    const checked = input.checked
    const previous = !checked

    if (!this.hasToggleUrlValue) return

    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")

    try {
      const res = await fetch(this.toggleUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html, application/json"
        },
        body: JSON.stringify({ checklist_id: id, checked })
      })

      if (!res.ok) {
        input.checked = previous
        return
      }

      const ct = (res.headers.get("Content-Type") || "").toLowerCase()
      if (ct.includes("vnd.turbo-stream") && typeof window.Turbo?.renderStreamMessage === "function") {
        const stream = await res.text()
        if (stream.trim()) window.Turbo.renderStreamMessage(stream)
      }
    } catch {
      input.checked = previous
    }
  }
}
