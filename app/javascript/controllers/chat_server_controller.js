import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["healthButton", "healthPanel", "healthList", "baseUrl", "modelSelect", "modelStatus"]

  static values = {
    healthUrl: String,
    listModelsUrl: String
  }

  markRoleDirty() {
    // URL 変更後は手動でモデル取得が必要。
  }

  async fetchModels(event) {
    event?.preventDefault()
    const role = event.currentTarget.dataset.role
    const row = event.currentTarget.closest("tr")
    if (!row || !role) return

    const baseUrlInput = row.querySelector('[data-chat-server-target="baseUrl"]')
    const modelSelect = row.querySelector('[data-chat-server-target="modelSelect"]')
    const statusEl = row.querySelector('[data-chat-server-target="modelStatus"]')
    const baseUrl = baseUrlInput?.value?.trim()

    if (!baseUrl) {
      this.setModelStatus(statusEl, "接続 URL を入力してください。", true)
      return
    }

    const button = event.currentTarget
    button.disabled = true
    button.textContent = "取得中…"
    this.setModelStatus(statusEl, "モデル一覧を取得中…", false)

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const res = await fetch(this.listModelsUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          ...(token ? { "X-CSRF-Token": token } : {})
        },
        body: JSON.stringify({ role, base_url: baseUrl })
      })

      const body = await res.json()
      if (!res.ok) {
        this.setModelStatus(statusEl, body.error || "モデル一覧の取得に失敗しました。", true)
        return
      }

      const savedModel = modelSelect?.dataset.savedModel || modelSelect?.value || ""
      this.populateModelSelect(modelSelect, body.models || [], savedModel)
      this.setModelStatus(statusEl, `${body.models.length} 件`, false)
    } catch (error) {
      this.setModelStatus(statusEl, error.message, true)
    } finally {
      button.disabled = false
      button.textContent = "モデル取得"
    }
  }

  populateModelSelect(select, models, preferred) {
    if (!select) return

    select.replaceChildren()

    const blank = document.createElement("option")
    blank.value = ""
    blank.textContent = "モデルを選択"
    select.append(blank)

    for (const modelId of models) {
      const option = document.createElement("option")
      option.value = modelId
      option.textContent = modelId
      select.append(option)
    }

    if (preferred && models.includes(preferred)) {
      select.value = preferred
    } else if (models.length === 1) {
      select.value = models[0]
    }
  }

  setModelStatus(element, message, isError) {
    if (!element) return

    element.textContent = message
    element.classList.toggle("hidden", !message)
    element.classList.toggle("kb-status-danger", isError)
    element.classList.toggle("kb-text-muted", !isError)
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
          "Content-Type": "application/json",
          ...(token ? { "X-CSRF-Token": token } : {})
        },
        body: JSON.stringify(this.collectRoleSettings())
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

  collectRoleSettings() {
    const roles = {}

    for (const row of this.element.querySelectorAll("tr[data-role]")) {
      const role = row.dataset.role
      if (!role) continue

      const baseUrl = row.querySelector('[data-chat-server-target="baseUrl"]')?.value?.trim() || ""
      const model = row.querySelector('[data-chat-server-target="modelSelect"]')?.value?.trim() || ""
      roles[role] = { base_url: baseUrl, model: model }
    }

    return { chat_server_settings: { roles } }
  }

  renderHealth(checks) {
    if (!this.hasHealthListTarget) return

    this.healthListTarget.innerHTML = checks.map((check) => {
      const statusClass = check.ok ? "kb-status-success" : "kb-status-danger"
      const label = check.role || "—"
      const url = check.base_url ? `<span class="font-mono text-xs kb-text-muted">${this.escapeHtml(check.base_url)}</span>` : ""
      const model = check.model ? `<span class="font-mono text-xs kb-text-muted">model: ${this.escapeHtml(check.model)}</span>` : ""
      return `<li class="rounded border px-3 py-2 kb-border">
        <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <span class="font-medium">${this.escapeHtml(label)}</span>
          <span class="text-sm ${statusClass}">${this.escapeHtml(check.message || (check.ok ? "OK" : "NG"))}</span>
        </div>
        ${url}
        ${model}
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
