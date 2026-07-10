import { Controller } from "@hotwired/stimulus"
import { subscribeAgentChat } from "../lib/agent_chat_cable"
import { appendChatMarkdown } from "../lib/chat_markdown"
import { buildChatStats, buildChatSteps } from "../lib/chat_activity"
import {
  buildInteractionLog,
  ChatStreamPanel,
  resolveAssistantReply
} from "../lib/chat_interactions"

export default class extends Controller {
  static targets = [
    "messages",
    "input",
    "sendButton",
    "error",
    "initialMessagesJson",
    "mcpToolsPanel",
    "mcpToolsButton",
    "mcpToolsList",
    "mcpToolsHint"
  ]

  static values = {
    chatUrl: String,
    settingsUrl: String,
    conversationId: String,
    nyoyToolsUrl: String,
    nyoyConfigured: Boolean
  }

  static storageKey = "agent_chat_enabled_mcp_tools"

  connect() {
    this.history = this.readInitialMessages()
    this.nyoyTools = []
    this.enabledMcpTools = this.readEnabledMcpTools()
    this.sending = false
    this.activityTracker = null
    this.streamPanel = null
    this.activeTurnId = null
    this.lastSeq = 0
    this.turnFinalized = false
    this.unsubscribeCable = subscribeAgentChat((event) => this.receivedCable(event))
    this.renderMessages()
    this.updateSendState()
    this.initialMessagesJsonTarget?.remove()
    if (this.nyoyConfiguredValue && this.nyoyToolsUrlValue) {
      this.fetchNyoyTools()
    }
  }

  disconnect() {
    this.stopActivityTracker()
    this.unsubscribeCable?.()
    this.unsubscribeCable = null
  }

  readInitialMessages() {
    if (!this.hasInitialMessagesJsonTarget) return []

    try {
      const raw = this.initialMessagesJsonTarget.textContent?.trim()
      if (!raw) return []
      const parsed = JSON.parse(raw)
      return Array.isArray(parsed) ? parsed : []
    } catch {
      return []
    }
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
        this.streamPanel?.appendInteraction({
          step_key: event.step_key,
          role: event.role,
          model: event.model,
          text: event.text,
          append: event.append
        })
        if (event.role === "thinking" || event.role === "response") {
          this.scrollMessages()
        }
        break
      case "tool_context":
        this.streamPanel?.appendInteraction({
          step_key: event.step_key,
          role: "tool",
          model: event.label,
          text: event.preview,
          append: false
        })
        break
      case "turn_finalized":
        if (
          this.finalizeAssistantTurn(
            this.normalizeTurnPayload(event.payload, event.conversation_id)
          )
        ) {
          this.clearError()
        }
        break
      case "turn_error":
        this.activeTurnId = null
        this.turnFinalized = false
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

  normalizeTurnPayload(payload, conversationId) {
    const data = payload && typeof payload === "object" ? { ...payload } : {}
    if (conversationId && !data.conversation_id) {
      data.conversation_id = conversationId
    }
    return data
  }

  sendOnEnter(event) {
    if (event.key !== "Enter") return
    if (!event.ctrlKey && !event.metaKey) return
    if (event.isComposing || event.keyCode === 229) return

    event.preventDefault()
    this.send(event)
  }

  readEnabledMcpTools() {
    try {
      const raw = window.localStorage.getItem(this.constructor.storageKey)
      if (!raw) return null
      const parsed = JSON.parse(raw)
      return Array.isArray(parsed) ? parsed.map(String) : null
    } catch {
      return null
    }
  }

  writeEnabledMcpTools(tools) {
    this.enabledMcpTools = tools
    if (tools == null) {
      window.localStorage.removeItem(this.constructor.storageKey)
      return
    }
    window.localStorage.setItem(this.constructor.storageKey, JSON.stringify(tools))
  }

  async fetchNyoyTools(event) {
    event?.preventDefault()
    if (!this.nyoyToolsUrlValue) return

    const button = this.hasMcpToolsButtonTarget ? this.mcpToolsButtonTarget : null
    if (button) {
      button.disabled = true
      button.textContent = "取得中…"
    }

    try {
      const res = await fetch(this.nyoyToolsUrlValue, {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
      const body = await res.json().catch(() => ({}))

      if (!res.ok) {
        this.setMcpToolsHint(body.error || "Nyoy MCP ツール一覧の取得に失敗しました。", true)
        return
      }

      this.nyoyTools = Array.isArray(body.tools) ? body.tools : []
      this.renderMcpToolsList()
      this.setMcpToolsHint(
        body.configured === false
          ? "Nyoy MCP が未設定です。"
          : `${this.nyoyTools.length} 件のツールを読み込みました。`,
        body.configured === false
      )
    } catch (error) {
      this.setMcpToolsHint(error.message, true)
    } finally {
      if (button) {
        button.disabled = false
        button.textContent = "ツール一覧を取得"
      }
    }
  }

  renderMcpToolsList() {
    if (!this.hasMcpToolsListTarget) return

    const list = this.mcpToolsListTarget
    list.replaceChildren()
    list.classList.remove("hidden")

    if (this.nyoyTools.length === 0) {
      const empty = document.createElement("p")
      empty.className = "text-xs kb-text-muted"
      empty.textContent = "利用可能なツールがありません。"
      list.append(empty)
      return
    }

    const enabled = new Set(this.enabledMcpTools || this.nyoyTools.map((tool) => tool.name))
    if (this.enabledMcpTools == null) {
      this.writeEnabledMcpTools([ ...enabled ])
    }

    const fieldset = document.createElement("fieldset")
    fieldset.className = "space-y-2"

    const legend = document.createElement("legend")
    legend.className = "sr-only"
    legend.textContent = "有効にする Nyoy MCP ツール"
    fieldset.append(legend)

    for (const tool of this.nyoyTools) {
      const row = document.createElement("label")
      row.className = "flex items-start gap-2 text-sm leading-snug"

      const checkbox = document.createElement("input")
      checkbox.type = "checkbox"
      checkbox.className = "mt-0.5"
      checkbox.value = tool.name
      checkbox.checked = enabled.has(tool.name)
      checkbox.addEventListener("change", () => this.syncEnabledMcpTools())

      const text = document.createElement("span")
      const title = document.createElement("span")
      title.className = "font-mono text-xs"
      title.textContent = tool.name

      text.append(title)
      if (tool.description) {
        text.append(document.createElement("br"))
        const desc = document.createElement("span")
        desc.className = "text-xs kb-text-muted"
        desc.textContent = tool.description
        text.append(desc)
      }

      row.append(checkbox, text)
      fieldset.append(row)
    }

    list.append(fieldset)
  }

  syncEnabledMcpTools() {
    if (!this.hasMcpToolsListTarget) return

    const selected = [
      ...this.mcpToolsListTarget.querySelectorAll('input[type="checkbox"]:checked')
    ].map((input) => input.value)

    this.writeEnabledMcpTools(selected)
  }

  setMcpToolsHint(message, isError = false) {
    if (!this.hasMcpToolsHintTarget) return

    this.mcpToolsHintTarget.textContent = message
    this.mcpToolsHintTarget.classList.toggle("kb-status-danger", isError)
    this.mcpToolsHintTarget.classList.toggle("kb-text-muted", !isError)
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
    this.turnFinalized = false

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
          turn_id: turnId,
          enabled_mcp_tools: this.enabledMcpTools
        })
      })

      const data = await res.json().catch(() => ({}))

      if (this.turnFinalized) {
        if (data.conversation_id) {
          this.conversationIdValue = String(data.conversation_id)
        }
        return
      }

      if (!res.ok) {
        this.stopActivityTracker()
        this.renderMessages()
        this.showError(data.error || "AI との通信に失敗しました。", {
          settingsUrl: data.settings_url
        })
        return
      }

      if (!this.finalizeAssistantTurn(this.normalizeTurnPayload(data, data.conversation_id))) {
        this.stopActivityTracker()
        this.renderMessages()
        this.showError("応答が空でした。")
      }
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

  finalizeAssistantTurn(payload) {
    if (this.turnFinalized) return true

    const reply = resolveAssistantReply({
      reply: payload.reply,
      trace: payload.trace,
      streamedPreview: ""
    })

    if (!reply.trim()) return false

    this.stopActivityTracker()

    if (payload.conversation_id) {
      this.conversationIdValue = String(payload.conversation_id)
    }

    this.history.push({
      role: "assistant",
      content: reply,
      activity: payload.trace || null
    })
    this.turnFinalized = true
    this.activeTurnId = null
    this.renderMessages()
    this.focusLatestAnswer()
    this.sending = false
    this.updateSendState()
    return true
  }

  focusLatestAnswer() {
    const answer = this.messagesTarget?.querySelector(".kb-ai-chat-answer:last-of-type")
    answer?.scrollIntoView({ block: "nearest" })
    this.scrollMessages()
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

    wrapper.append(header)

    const answerText = isUser
      ? String(entry.content ?? "")
      : resolveAssistantReply({
          reply: entry.content,
          trace: entry.activity,
          streamedPreview: ""
        })

    if (isUser) {
      const bubble = document.createElement("div")
      bubble.className =
        "kb-ai-chat-answer rounded-md px-3 py-2 text-sm leading-relaxed kb-ai-message-user"
      this.appendTextWithLineBreaks(bubble, answerText)
      wrapper.append(bubble)
      return wrapper
    }

    if (entry.activity?.steps?.length) {
      const stepsWrap = document.createElement("div")
      stepsWrap.className = "kb-ai-chat-activity kb-ai-chat-activity-steps"
      stepsWrap.append(buildChatSteps(entry.activity.steps))
      wrapper.append(stepsWrap)
    }

    if (entry.activity?.interactions?.length) {
      const logLabel = document.createElement("p")
      logLabel.className = "kb-ai-chat-log-label kb-text-muted"
      logLabel.textContent = "モデル詳細"
      wrapper.append(logLabel, buildInteractionLog(entry.activity.interactions))
    }

    const answerLabel = document.createElement("p")
    answerLabel.className = "kb-ai-chat-answer-label kb-text-muted"
    answerLabel.textContent = "回答"
    wrapper.append(answerLabel)

    const bubble = document.createElement("div")
    bubble.className =
      "kb-ai-chat-answer rounded-md px-3 py-2 text-sm leading-relaxed kb-ai-message-assistant"

    if (answerText.trim()) {
      appendChatMarkdown(bubble, answerText)
    } else {
      bubble.classList.add("kb-text-muted")
      bubble.textContent = "（応答なし）"
    }

    wrapper.append(bubble)

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
