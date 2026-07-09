import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["healthButton", "healthPanel", "healthList"]

  static values = {
    healthUrl: String
  }

  async checkHealth(event) {
    event?.preventDefault()
    if (!this.healthUrlValue) {
      this.showHealthError("接続確認 URL が設定されていません。")
      return
    }

    const button = this.hasHealthButtonTarget ? this.healthButtonTarget : null
    if (button) {
      button.disabled = true
      button.textContent = "確認中…"
    }

    this.healthPanelTarget?.classList.remove("hidden")
    if (this.hasHealthListTarget) {
      this.healthListTarget.innerHTML = '<li class="text-sm kb-text-muted">確認中…</li>'
    }

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const res = await fetch(this.healthUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          ...(token ? { "X-CSRF-Token": token } : {})
        }
      })

      const body = await res.json()
      this.renderHealth(body.checks || [])
    } catch (error) {
      this.renderHealth([{ role: "—", base_url: "", ok: false, message: error.message }])
    } finally {
      if (button) {
        button.disabled = false
        button.textContent = "接続確認"
      }
    }
  }

  renderHealth(checks) {
    if (!this.hasHealthListTarget) return

    this.healthListTarget.innerHTML = checks.map((check) => {
      const statusClass = check.ok ? "kb-status-success" : "kb-status-danger"
      const label = check.role || "—"
      const url = check.base_url ? `<span class="font-mono text-xs kb-text-muted">${this.escapeHtml(check.base_url)}</span>` : ""
      return `<li class="rounded border px-3 py-2 kb-border">
        <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <span class="font-medium">${this.escapeHtml(label)}</span>
          <span class="text-sm ${statusClass}">${this.escapeHtml(check.message || (check.ok ? "OK" : "NG"))}</span>
        </div>
        ${url}
      </li>`
    }).join("")
  }

  escapeHtml(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }

  showHealthError(message) {
    this.healthPanelTarget?.classList.remove("hidden")
    this.renderHealth([{ role: "—", base_url: "", ok: false, message }])
  }
}
