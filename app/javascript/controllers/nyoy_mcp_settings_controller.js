import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["testButton", "resultPanel", "resultMessage", "toolsList"]

  static values = {
    testUrl: String
  }

  async testConnection(event) {
    event?.preventDefault()
    if (!this.testUrlValue) return

    const button = this.hasTestButtonTarget ? this.testButtonTarget : null
    if (button) {
      button.disabled = true
      button.textContent = "確認中…"
    }

    this.resultPanelTarget?.classList.remove("hidden")
    if (this.hasResultMessageTarget) {
      this.resultMessageTarget.textContent = "接続確認中…"
      this.resultMessageTarget.className = "mt-2 text-sm kb-text-muted"
    }
    if (this.hasToolsListTarget) {
      this.toolsListTarget.innerHTML = ""
    }

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const res = await fetch(this.testUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          ...(token ? { "X-CSRF-Token": token } : {})
        }
      })

      const body = await res.json()
      if (!res.ok) {
        this.showResult(body.message || "接続に失敗しました。", false)
        return
      }

      this.showResult(body.message || "OK", true)
      this.renderTools(body.tools || [])
    } catch (error) {
      this.showResult(error.message, false)
    } finally {
      if (button) {
        button.disabled = false
        button.textContent = "接続確認"
      }
    }
  }

  showResult(message, ok) {
    if (!this.hasResultMessageTarget) return

    this.resultMessageTarget.textContent = message
    this.resultMessageTarget.className = `mt-2 text-sm ${ok ? "kb-status-success" : "kb-status-danger"}`
  }

  renderTools(tools) {
    if (!this.hasToolsListTarget) return

    if (tools.length === 0) {
      this.toolsListTarget.innerHTML = '<li class="text-sm kb-text-muted">ツールがありません。</li>'
      return
    }

    this.toolsListTarget.innerHTML = tools.map((tool) => {
      const name = this.escapeHtml(tool.name || "—")
      const description = tool.description ? `<p class="mt-1 text-xs kb-text-muted">${this.escapeHtml(tool.description)}</p>` : ""
      return `<li class="rounded border px-3 py-2 kb-border">
        <p class="font-mono text-xs">${name}</p>
        ${description}
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
}
