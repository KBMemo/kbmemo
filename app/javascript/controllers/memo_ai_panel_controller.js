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

    if (!this.hasApiKeyValue) {
      this.showError("OpenAI API キーをプロフィールで設定してください。")
      return
    }

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
        let message = data.error || "AI との通信に失敗しました。"
        if (data.settings_url) {
          message = `${message} ${this.profileLinkHtml(data.settings_url)}`
        }
        this.showError(message)
        return
      }

      const reply = (data.reply || "").trim()
      if (!reply) {
        this.showError("応答が空でした。")
        return
      }

      this.history.push({ role: "assistant", content: reply })
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

    if (this.history.length === 0) {
      this.messagesTarget.innerHTML = `<p class="text-xs kb-text-muted">メモの執筆・推敲を手伝います。送信すると本文の抜粋が OpenAI に送られます。</p>`
      return
    }

    const html = this.history
      .map((entry) => {
        const isUser = entry.role === "user"
        const label = isUser ? "あなた" : "AI"
        const bubble = isUser ? "bg-[var(--kb-bg-muted)] kb-text-primary" : "bg-emerald-50 text-emerald-950"
        const escaped = this.escapeHtml(entry.content).replace(/\n/g, "<br>")
        return `<div class="mb-3"><p class="mb-0.5 text-[10px] font-medium uppercase tracking-wide kb-text-muted">${label}</p><div class="rounded-md px-2 py-1.5 text-xs leading-relaxed ${bubble}">${escaped}</div></div>`
      })
      .join("")

    this.messagesTarget.innerHTML = html
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  updateSendState() {
    if (!this.hasSendButtonTarget) return
    this.sendButtonTarget.disabled = this.sending
    this.sendButtonTarget.textContent = this.sending ? "送信中…" : "送信"
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.innerHTML = message
    this.errorTarget.classList.remove("hidden")
  }

  clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  profileLinkHtml(url) {
    const safe = this.escapeHtml(url)
    return `<a href="${safe}" class="underline">プロフィール</a>`
  }

  escapeHtml(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
