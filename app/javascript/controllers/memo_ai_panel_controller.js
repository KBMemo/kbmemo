import { Controller } from "@hotwired/stimulus"
import { appendChatMarkdown } from "../lib/chat_markdown"

const MODEL_ROLE_STORAGE_KEY = "kbmemo_memo_ai_model_role_v1"

export default class extends Controller {
  static targets = [
    "messages",
    "input",
    "sendButton",
    "insertButton",
    "error",
    "status",
    "includeSelection",
    "modelRole"
  ]

  static values = {
    chatUrl: String,
    appendUrl: String,
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

  disconnect() {
    if (this.statusTimer) window.clearTimeout(this.statusTimer)
  }

  modelRoleChanged() {
    if (!this.hasModelRoleTarget) return
    try {
      localStorage.setItem(MODEL_ROLE_STORAGE_KEY, this.modelRoleTarget.value)
    } catch {
      // Storage can be unavailable in privacy-restricted browser contexts.
    }
  }

  sendOnEnter(event) {
    if (event.key !== "Enter") return
    if (!event.ctrlKey && !event.metaKey) return
    if (event.isComposing || event.keyCode === 229) return

    event.preventDefault()
    this.send(event)
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

    const includeSelection = this.includeSelectionEnabled()
    const editor = this.bodyEditorController()
    const editorContext = editor?.getEditContext ? await editor.getEditContext() : null
    if (editorContext && !includeSelection) editorContext.selection = ""
    const selection = includeSelection
      ? (editorContext?.selection || this.selectedEditorText() || "")
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
          editor_context: editorContext,
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
      await this.applyEditFromResponse(data.edit, { includeSelection })
    } catch {
      this.showError("AI との通信に失敗しました。")
    } finally {
      this.sending = false
      this.updateSendState()
    }
  }

  async insertLastReply(event) {
    event?.preventDefault()
    const last = [...this.history].reverse().find((m) => m.role === "assistant")
    if (!last?.content) {
      this.showError("挿入する応答がありません。")
      return
    }
    const editor = this.bodyEditorController()
    if (editor) {
      await editor.insertAtCursor(last.content)
      this.clearError()
      this.showStatus("応答をカーソル位置へ挿入しました。")
      return
    }
    if (!this.hasAppendUrlValue) {
      this.showError("本文エディタの準備ができていません。")
      return
    }

    this.setInsertBusy(true)
    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const res = await fetch(this.appendUrlValue, {
        method: "PATCH",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          ...(token ? { "X-CSRF-Token": token } : {})
        },
        body: JSON.stringify({ content: last.content })
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        this.showError(data.error || "応答をメモへ追記できませんでした。")
        return
      }
      this.clearError()
      this.showStatus("応答をメモ末尾へ追記しました。")
    } catch {
      this.showError("応答をメモへ追記できませんでした。")
    } finally {
      this.setInsertBusy(false)
    }
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

  includeSelectionEnabled() {
    return !this.hasIncludeSelectionTarget || this.includeSelectionTarget.checked
  }

  async applyEditFromResponse(edit, { includeSelection } = {}) {
    const target = String(edit?.target || "none")
    if (target === "none") return

    const editor = this.bodyEditorController()
    if (!editor?.applyAiEdit) return

    if (target === "selection" && !includeSelection) {
      this.showError("選択範囲の置換は、選択範囲をコンテキストに含める設定がオフのため適用しませんでした。")
      return
    }

    try {
      const result = await editor.applyAiEdit(edit)
      if (result?.applied) {
        this.showStatus(`${this.statusForAppliedEdit(result)} 元に戻すなら Ctrl+Z またはドラフト復元が使えます。`)
        return
      }
      if (result?.error) this.showError(result.error)
    } catch {
      this.showError("本文への適用に失敗しました。")
    }
  }

  statusForAppliedEdit(result) {
    if (result.target === "selection") return "選択範囲を書き換えました。"
    if (result.target === "section") return "この節を書き換えました。"
    if (result.target === "body") return "本文を整形しました。"
    if (result.target === "unit" && result.kind === "table") return "表を書き換えました。"
    if (result.target === "unit" && result.kind === "list") return "箇条書きを書き換えました。"
    if (result.target === "unit") return "ブロックを書き換えました。"
    return "本文を更新しました。"
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
      this.messagesTarget.classList.add("hidden")
      return
    }

    this.messagesTarget.classList.remove("hidden")
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

  setInsertBusy(busy) {
    if (!this.hasInsertButtonTarget) return
    this.insertButtonTarget.disabled = busy
    this.insertButtonTarget.textContent = busy ? "追記中…" : "応答を末尾へ追記"
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
    this.clearStatus()
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

  showStatus(message) {
    if (!this.hasStatusTarget) return
    this.clearStatus()
    this.statusTarget.textContent = String(message)
    this.statusTarget.classList.remove("hidden")
    this.statusTimer = window.setTimeout(() => this.clearStatus(), 4000)
  }

  clearStatus() {
    if (this.statusTimer) {
      window.clearTimeout(this.statusTimer)
      this.statusTimer = null
    }
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = ""
    this.statusTarget.classList.add("hidden")
  }

}
