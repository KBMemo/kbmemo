import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "toggleIcon", "row"]
  static values = { expanded: { type: Boolean, default: false } }

  connect() {
    this.syncPanel()
  }

  toggle() {
    this.expandedValue = !this.expandedValue
  }

  expandedValueChanged() {
    this.syncPanel()
  }

  syncPanel() {
    if (this.hasPanelTarget) {
      this.panelTarget.classList.toggle("hidden", !this.expandedValue)
    }
    if (this.hasToggleIconTarget) {
      this.toggleIconTarget.textContent = this.expandedValue ? "▲" : "▼"
    }
    const toggleBtn = this.element.querySelector("[data-action*='memo-attachments#toggle']")
    if (toggleBtn) {
      toggleBtn.setAttribute("aria-expanded", this.expandedValue ? "true" : "false")
      toggleBtn.title = this.expandedValue ? "添付ファイル一覧を閉じる" : "添付ファイル一覧を開く"
    }
  }

  insert(event) {
    const text = event.params.text
    if (!text) return

    const editorEl = this.element.closest("[data-controller~='memo-body-editor']")
    if (!editorEl) return

    editorEl.dispatchEvent(
      new CustomEvent("memo-body-editor:insert", {
        bubbles: true,
        detail: { text }
      })
    )
  }

  async remove(event) {
    const button = event.currentTarget
    const assetPath = button.getAttribute("data-destroy-path")
    const memoId = button.getAttribute("data-memo-id")
    const name = button.getAttribute("data-destroy-name") || "ファイル"
    if (!assetPath || !memoId) return
    if (!window.confirm(`${name} を削除しますか？`)) return

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const url = `/memos/${memoId}/assets`

    try {
      const res = await fetch(url, {
        method: "DELETE",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          ...(token ? { "X-CSRF-Token": token } : {})
        },
        credentials: "same-origin",
        redirect: "manual",
        body: JSON.stringify({ asset_path: assetPath })
      })

      if (res.status !== 204) {
        let message = "削除に失敗しました"
        const contentType = res.headers.get("Content-Type") || ""
        if (contentType.includes("application/json")) {
          try {
            const data = await res.json()
            if (data.error) message = data.error
          } catch {
            /* ignore */
          }
        }
        window.alert(message)
        return
      }

      const row = button.closest("[data-memo-attachments-target='row']")
      if (row) row.remove()

      if (this.hasPanelTarget && this.panelTarget.querySelectorAll("[data-memo-attachments-target='row']").length === 0) {
        const empty = document.createElement("p")
        empty.className = "px-1 py-2 text-xs kb-text-muted"
        empty.textContent = "添付ファイルはありません"
        this.panelTarget.appendChild(empty)
      }
    } catch {
      window.alert("削除に失敗しました")
    }
  }
}
