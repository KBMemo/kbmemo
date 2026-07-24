import { Controller } from "@hotwired/stimulus"
import { appendChatMarkdown } from "../lib/chat_markdown"

const MODEL_ROLE_STORAGE_KEY = "kbmemo_memo_ai_model_role_v1"

export default class extends Controller {
  static targets = [
    "messages",
    "input",
    "sendButton",
    "error",
    "includeSelection",
    "modelRole"
  ]

  static values = {
    chatUrl: String,
    modelOptionsUrl: String,
    profileUrl: String,
    hasApiKey: Boolean
  }

  connect() {
    this.history = []
    this.sending = false
    this.restoreModelRole()
    void this.refreshModelOptions()
    this.renderMessages()
    this.updateSendState()
  }

  modelRoleChanged() {
    if (!this.hasModelRoleTarget) return
    try {
      localStorage.setItem(MODEL_ROLE_STORAGE_KEY, this.modelRoleTarget.value)
    } catch {
      // Storage can be unavailable in privacy-restricted browser contexts.
    }
  }

  async refreshModelOptions() {
    if (!this.hasModelRoleTarget || !this.hasModelOptionsUrlValue) return

    const selected = this.savedModelRole() || this.modelRoleTarget.value
    try {
      const res = await fetch(this.modelOptionsUrlValue, {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok || !Array.isArray(data.options) || data.options.length === 0) return

      this.modelRoleTarget.replaceChildren(
        ...data.options.map((entry) => {
          const option = document.createElement("option")
          option.value = String(entry.role)
          option.textContent = `${entry.label} · ${entry.model}`
          return option
        })
      )
      const available = [...this.modelRoleTarget.options].some((option) => option.value === selected)
      if (available) this.modelRoleTarget.value = selected
    } catch {
      // Keep server-rendered options when refresh is unavailable.
    }
  }

  async send(event) {
    event?.preventDefault()
    if (this.sending) return

    const text = this.inputTarget?.value?.trim()
    if (!text) return

    this.clearError()
    this.history.push({ role: "user", content: text })
    if (this.inputTarget) this.inputTarget.value = ""
    this.renderMessages()
    this.sending = true
    this.updateSendState()

    const selection =
      this.hasIncludeSelectionTarget && this.includeSelectionTarget.checked
        ? this.selectedEditorText()
        : ""

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const res = await fetch(this.chatUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          ...(token ? { "X-CSRF-Token": token } : {})
        },
        body: JSON.stringify({
          messages: this.history,
          selection: selection || null,
          model_role: this.selectedModelRole()
        })
      })

      const data = await res.json().catch(() => ({}))

      if (!res.ok) {
        this.showError(data.error || "AI との通信に失敗しました。", {
          settingsUrl: data.settings_url
        })
        return
      }

      const reply = (data.reply || "").trim()
      if (!reply) {
        this.showError("応答が空でした。")
        return
      }

      this.history.push({
        role: "assistant",
        content: reply,
        backend: data.backend,
        model: data.model
      })
      this.renderMessages()
    } catch {
      this.showError("AI との通信に失敗しました。")
    } finally {
      this.sending = false
      this.updateSendState()
    }
  }

  insertLastReply(event) {
    event?.preventDefault()
    const last = [...this.history].reverse().find((m) => m.role === "assistant")
    if (!last?.content) {
      this.showError("挿入する応答がありません。")
      return
    }
    const editor = this.bodyEditorController()
    if (!editor) {
      this.showError("本文エディタの準備ができていません。")
      return
    }
    void editor.insertAtCursor(last.content)
    this.clearError()
  }

  clearChat(event) {
    event?.preventDefault()
    this.history = []
    this.renderMessages()
    this.clearError()
  }

  selectedEditorText() {
    const editor = this.bodyEditorController()
    return editor?.getSelectedText?.() || ""
  }

  bodyEditorController() {
    const el = document.querySelector(
      "#memos_editor_scroll [data-controller~=\"memo-body-editor\"]"
    )
    if (!el) return null
    return this.application.getControllerForElementAndIdentifier(el, "memo-body-editor")
  }

  renderMessages() {
    if (!this.hasMessagesTarget) return

    this.messagesTarget.replaceChildren()

    if (this.history.length === 0) return

    for (const entry of this.history) {
      this.messagesTarget.append(this.messageNode(entry))
    }
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  messageNode(entry) {
    const isUser = entry.role === "user"
    const wrapper = document.createElement("div")
    wrapper.className = "mb-3"

    const label = document.createElement("p")
    label.className = "mb-0.5 kb-ai-message-label font-medium uppercase tracking-wide kb-text-muted"
    label.textContent = isUser ? "あなた" : "AI"

    if (!isUser && (entry.model || entry.backend)) {
      const badge = document.createElement("span")
      badge.className = "ml-1 normal-case kb-text-muted"
      badge.textContent = entry.model
        ? `· ${entry.model}`
        : entry.backend === "openai" ? "· OpenAI" : "· ローカル"
      label.append(badge)
    }

    const bubble = document.createElement("div")
    bubble.className = `rounded-md px-2 py-1.5 text-xs leading-relaxed ${
      isUser ? "kb-ai-message-user" : "kb-ai-message-assistant"
    }`
    if (isUser) {
      this.appendTextWithLineBreaks(bubble, entry.content)
    } else {
      appendChatMarkdown(bubble, entry.content)
    }

    wrapper.append(label, bubble)
    return wrapper
  }

  appendTextWithLineBreaks(container, text) {
    const lines = String(text ?? "").split("\n")
    lines.forEach((line, index) => {
      if (index > 0) container.append(document.createElement("br"))
      container.append(document.createTextNode(line))
    })
  }

  updateSendState() {
    if (!this.hasSendButtonTarget) return
    this.sendButtonTarget.disabled = this.sending
    this.sendButtonTarget.textContent = this.sending ? "送信中…" : "送信"
  }

  selectedModelRole() {
    return this.hasModelRoleTarget ? this.modelRoleTarget.value : "main"
  }

  restoreModelRole() {
    if (!this.hasModelRoleTarget) return
    const saved = this.savedModelRole()
    const available = [...this.modelRoleTarget.options].some((option) => option.value === saved)
    if (available) this.modelRoleTarget.value = saved
  }

  savedModelRole() {
    try {
      return localStorage.getItem(MODEL_ROLE_STORAGE_KEY) || ""
    } catch {
      return ""
    }
  }

  showError(message, options = {}) {
    if (!this.hasErrorTarget) return
    this.errorTarget.replaceChildren()
    this.errorTarget.append(document.createTextNode(String(message)))

    if (options.settingsUrl) {
      this.errorTarget.append(" ")
      const link = document.createElement("a")
      link.href = String(options.settingsUrl)
      link.className = "underline"
      link.textContent = "設定を開く"
      this.errorTarget.append(link)
    }

    this.errorTarget.classList.remove("hidden")
  }

  clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

}
