import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { appendChatMarkdown } from "../lib/chat_markdown"
import { buildChatStats, buildChatSteps } from "../lib/chat_activity"
import { buildInteractionLog, ChatStreamPanel } from "../lib/chat_interactions"

const cable = createConsumer()

export default class extends Controller {
  static targets = ["messages", "input", "sendButton", "error"]

  static values = {
    chatUrl: String,
    settingsUrl: String,
    conversationId: String,
    initialMessages: Array,
    cableUrl: { type: String, default: "/cable" }
  }

  connect() {
    this.history = Array.isArray(this.initialMessagesValue) ? [...this.initialMessagesValue] : []
    this.sending = false
    this.activityTracker = null
    this.streamPanel = null
    this.activeTurnId = null
    this.lastSeq = 0
    this.subscribeCable()
    this.renderMessages()
    this.updateSendState()
  }

  disconnect() {
    this.stopActivityTracker()
    this.cableSubscription?.unsubscribe()
  }

  subscribeCable() {
    this.cableSubscription = cable.subscriptions.create("AgentChatAccountChannel", {
      received: (event) => this.receivedCable(event)
    })
  }

  receivedCable(event) {
    if (!this.activeTurnId || event.turn_id !== this.activeTurnId) return
    if (event.seq != null && event.seq <= this.lastSeq) return
    if (event.seq != null) this.lastSeq = event.seq

    switch (event.type) {
      case "turn_started":
        if (event.conversation_id) {
          this.conversationIdValue = String(event.conversation_id)
        }
        break
      case "trace_step":
        this.streamPanel?.upsertTraceStep(event.step, event.phase)
        break
      case "interaction":
      case "tool_context":
        this.streamPanel?.appendInteraction({
          step_key: event.step_key,
          role: event.type === "tool_context" ? "tool" : event.role,
          model: event.type === "tool_context" ? event.label : event.model,
          text: event.type === "tool_context" ? event.preview : event.text,
          append: event.append
        })
        break
      case "assistant_delta":
        this.streamPanel?.appendAssistantDelta(event.text, { thinking: event.thinking })
        this.scrollMessages()
        break
      case "turn_error":
        this.stopActivityTracker()
        this.renderMessages()
        this.showError(event.error || "AI との通信に失敗しました。", {
          settingsUrl: event.settings_url
        })
        this.sending = false
        this.updateSendState()
        break
      default:
        break
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
    this.startActivityPanel()

    const turnId = crypto.randomUUID()
    this.activeTurnId = turnId
    this.lastSeq = 0

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
          conversation_id: this.conversationIdValue || null,
          turn_id: turnId
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
        activity: data.trace || null
      })
      this.activeTurnId = null
      this.renderMessages()
    } catch {
      this.showError("AI との通信に失敗しました。")
      this.stopActivityTracker()
      this.activeTurnId = null
      this.renderMessages()
    } finally {
      this.sending = false
      this.updateSendState()
    }
  }

  startActivityPanel() {
    if (!this.hasMessagesTarget) return

    this.stopActivityTracker()
    this.streamPanel = new ChatStreamPanel()
    this.activityPanel = this.streamPanel.element()
    this.messagesTarget.append(this.activityPanel)
    this.scrollMessages()

    this.activityTracker = window.setInterval(() => {
      if (!this.streamPanel) return
      const elapsed = this.activityPanel?._startedAt
        ? performance.now() - this.activityPanel._startedAt
        : 0
      this.streamPanel.setElapsed(elapsed)
    }, 100)
    this.activityPanel._startedAt = performance.now()
    this.streamPanel.setElapsed(0)
  }

  stopActivityTracker() {
    if (this.activityTracker != null) {
      window.clearInterval(this.activityTracker)
      this.activityTracker = null
    }
    this.streamPanel = null
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
    this.activeTurnId = null
    this.stopActivityTracker()
    this.renderMessages()
    this.clearError()
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

    this.scrollMessages()
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
    }

    if (!isUser && entry.activity?.interactions?.length) {
      wrapper.append(buildInteractionLog(entry.activity.interactions))
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

  scrollMessages() {
    if (!this.hasMessagesTarget) return
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
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
