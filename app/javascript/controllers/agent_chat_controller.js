import { Controller } from "@hotwired/stimulus"
import { appendChatMarkdown } from "../lib/chat_markdown"
import { buildChatActivity, buildChatStats, buildChatSteps, ChatActivityTracker } from "../lib/chat_activity"

export default class extends Controller {
  static targets = ["messages", "input", "sendButton", "error"]

  static values = {
    chatUrl: String,
    settingsUrl: String,
    conversationId: String,
    initialMessages: Array
  }

  connect() {
    this.history = Array.isArray(this.initialMessagesValue) ? [...this.initialMessagesValue] : []
    this.sending = false
    this.activityTracker = null
    this.activityPanel = null
    this.renderMessages()
    this.updateSendState()
  }

  disconnect() {
    this.stopActivityTracker()
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
    this.startActivityPanel()

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
          conversation_id: this.conversationIdValue || null
        })
      })

      const data = await res.json().catch(() => ({}))

      if (!res.ok) {
        this.stopActivityTracker()
        this.renderMessages()
        this.showError(data.error || "AI との通信に失敗しました。", {
          settingsUrl: data.settings_url
        })
        return
      }

      const reply = (data.reply || "").trim()
      if (!reply) {
        this.stopActivityTracker()
        this.renderMessages()
        this.showError("応答が空でした。")
        return
      }

      if (data.conversation_id) {
        this.conversationIdValue = String(data.conversation_id)
      }

      this.stopActivityTracker()
      this.history.push({
        role: "assistant",
        content: reply,
        activity: data.trace || null,
        meta: data.trace ? null : this.metaFromResponse(data)
      })
      this.renderMessages()
    } catch {
      this.showError("AI との通信に失敗しました。")
      this.stopActivityTracker()
      this.renderMessages()
    } finally {
      this.sending = false
      this.updateSendState()
    }
  }

  startActivityPanel() {
    if (!this.hasMessagesTarget) return

    this.stopActivityTracker()
    this.activityPanel = buildChatActivity({ running: true, elapsedMs: 0 })
    this.messagesTarget.append(this.activityPanel)
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight

    this.activityTracker = new ChatActivityTracker({
      onTick: (elapsedMs) => {
        const elapsed = this.activityPanel?.querySelector("[data-chat-activity-elapsed]")
        if (elapsed) elapsed.textContent = `${(elapsedMs / 1000).toFixed(1)}秒`
      }
    })
    this.activityTracker.start()
  }

  stopActivityTracker() {
    this.activityTracker?.stop()
    this.activityTracker = null
    this.activityPanel = null
  }

  async clearChat(event) {
    event?.preventDefault()

    if (this.conversationIdValue) {
      try {
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        const url = new URL(this.chatUrlValue, window.location.origin)
        url.searchParams.set("conversation_id", this.conversationIdValue)
        await fetch(url.toString(), {
          method: "DELETE",
          credentials: "same-origin",
          headers: {
            Accept: "application/json",
            ...(token ? { "X-CSRF-Token": token } : {})
          }
        })
      } catch {
        // ローカル表示は消す。サーバ削除失敗時も UI はリセットする。
      }
    }

    this.history = []
    this.conversationIdValue = ""
    this.stopActivityTracker()
    this.renderMessages()
    this.clearError()
  }

  metaFromResponse(data) {
    const parts = []
    if (data.intent) parts.push(`intent: ${data.intent}`)
    if (data.model_role) {
      let model = String(data.model_role)
      if (data.escalated) model += " (escalated)"
      parts.push(`model: ${model}`)
    }
    if (data.rag?.hit_count > 0) {
      let rag = `RAG: ${data.rag.hit_count}件`
      if (data.rag.semantic_used) rag += " · semantic"
      parts.push(rag)
    }
    if (data.mcp?.tools_run?.length) {
      parts.push(`MCP: ${data.mcp.tools_run.join(", ")}`)
    }
    if (data.pending_tools) parts.push("tools: pending")
    return parts.length > 0 ? parts.join(" · ") : null
  }

  renderMessages() {
    if (!this.hasMessagesTarget) return

    this.messagesTarget.replaceChildren()

    if (this.history.length === 0) {
      const empty = document.createElement("p")
      empty.className = "text-sm kb-text-muted leading-relaxed"
      empty.textContent =
        "メモ検索（RAG）・技術相談・一般チャットなどを intent に応じてルーティングします。ローカル llama-server が未起動のときは OpenAI キーがあればフォールバックします。"
      this.messagesTarget.append(empty)
      return
    }

    for (const entry of this.history) {
      this.messagesTarget.append(this.messageNode(entry))
    }

    if (this.sending && this.activityPanel) {
      this.messagesTarget.append(this.activityPanel)
    }

    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  messageNode(entry) {
    const isUser = entry.role === "user"
    const wrapper = document.createElement("div")
    wrapper.className = "mb-4"

    const header = document.createElement("div")
    header.className = "kb-ai-message-header"

    const label = document.createElement("p")
    label.className =
      "mb-0 kb-ai-message-label font-medium uppercase tracking-wide kb-text-muted"
    label.textContent = isUser ? "あなた" : "AI"
    header.append(label)

    if (!isUser && entry.activity?.stats?.length) {
      header.append(buildChatStats(entry.activity.stats))
    }

    const bubble = document.createElement("div")
    bubble.className = `rounded-md px-3 py-2 text-sm leading-relaxed ${
      isUser ? "kb-ai-message-user" : "kb-ai-message-assistant"
    }`
    if (isUser) {
      this.appendTextWithLineBreaks(bubble, entry.content)
    } else {
      appendChatMarkdown(bubble, entry.content)
    }

    wrapper.append(header, bubble)

    if (!isUser && entry.activity?.steps?.length) {
      const stepsWrap = document.createElement("div")
      stepsWrap.className = "kb-ai-chat-activity kb-ai-chat-activity-steps"
      stepsWrap.append(buildChatSteps(entry.activity.steps))
      wrapper.append(stepsWrap)
    } else if (!isUser && entry.meta) {
      const meta = document.createElement("p")
      meta.className = "mt-1 text-xs kb-text-muted"
      meta.textContent = entry.meta
      wrapper.append(meta)
    }

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
