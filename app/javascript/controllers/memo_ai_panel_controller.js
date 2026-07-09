import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "input", "sendButton", "error", "includeSelection"]

  static values = {
    chatUrl: String,
    profileUrl: String,
    hasApiKey: Boolean
  }

  connect() {
    this.history = []
    this.sending = false
    this.renderMessages()
    this.updateSendState()
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
          selection: selection || null
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

      this.history.push({ role: "assistant", content: reply, backend: data.backend })
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

    if (this.history.length === 0) {
      const empty = document.createElement("p")
      empty.className = "text-xs kb-text-muted"
      empty.textContent = "メモの執筆・推敲を手伝います。既定でローカル AI を使います。"
      this.messagesTarget.append(empty)
      return
    }

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

    if (!isUser && entry.backend) {
      const badge = document.createElement("span")
      badge.className = "ml-1 normal-case kb-text-muted"
      badge.textContent = entry.backend === "openai" ? "· OpenAI" : "· ローカル"
      label.append(badge)
    }

    const bubble = document.createElement("div")
    bubble.className = `rounded-md px-2 py-1.5 text-xs leading-relaxed ${
      isUser ? "kb-ai-message-user" : "kb-ai-message-assistant"
    }`
    this.appendTextWithLineBreaks(bubble, entry.content)

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
