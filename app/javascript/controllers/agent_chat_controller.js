import { Controller } from "@hotwired/stimulus"
import { subscribeAgentChat } from "../lib/agent_chat_cable"
import { appendChatMarkdown } from "../lib/chat_markdown"
import { buildChatStats, buildChatSteps } from "../lib/chat_activity"
import {
  csrfFetchHeaders,
  isCsrfErrorResponse,
  jsonRequestHeaders,
  withAuthenticityToken
} from "../lib/csrf_fetch"
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
    "initialMemoReferencesJson",
    "mcpToolsPanel",
    "mcpToolsButton",
    "mcpToolsList",
    "mcpToolsHint",
    "fileInput",
    "attachmentList",
    "attachmentError",
    "tsuzuraDialog",
    "tsuzuraAlbumList",
    "tsuzuraMediaList",
    "tsuzuraStatus",
    "tsuzuraConfirmButton",
    "memoDialog",
    "memoSearch",
    "memoStatus",
    "memoResults",
    "memoConfirmButton",
    "memoReferenceList",
    "memoReferenceCount",
    "memoImageDialog",
    "memoImageSearch",
    "memoImageStatus",
    "memoImageResults",
    "memoImageConfirmButton",
    "memoImageDialogTitle",
    "referenceMemoImageButton",
    "memoImageLoadMoreWrap",
    "memoImageLoadMoreButton",
    "recordButton",
    "audioStatus"
  ]

  static values = {
    chatUrl: String,
    newChatUrl: String,
    settingsUrl: String,
    nyoyMcpUrl: String,
    imageGenerationUrlTemplate: String,
    refineImageGenerationUrlTemplate: String,
    conversationId: String,
    nyoyToolsUrl: String,
    nyoyConfigured: Boolean,
    uploadImageUrl: String,
    memoImagesUrl: String,
    uploadMemoImageUrl: String,
    tsuzuraAlbumsUrl: String,
    tsuzuraAlbumUrlTemplate: String,
    memoReferencesUrl: String,
    memoUrlTemplate: String,
    transcribeAudioUrl: String,
    synthesizeAudioUrl: String
  }

  static storageKey = "agent_chat_enabled_mcp_tools"

  static pendingToolLabels = {
    web_search: "Web 検索",
    fetch_url: "URL 取得",
    image_generation: "画像生成",
    image_analysis: "画像解析",
    memo_add: "メモ作成"
  }

  connect() {
    this.history = this.readInitialMessages()
    this.nyoyTools = []
    this.enabledMcpTools = this.readEnabledMcpTools()
    this.pendingAttachments = []
    this.pendingMemoReferences = this.readInitialMemoReferences()
    this.memoSearchResults = []
    this.memoSelectedIds = new Set()
    this.memoSearchTimer = null
    this.memoReferenceSyncVersion = 0
    this.tsuzuraSelectedIds = new Set()
    this.memoImageResults = []
    this.memoImageSelections = new Map()
    this.memoImageSearchTimer = null
    this.memoImageReferenceOnly = false
    this.memoImageNextCursor = null
    this.memoImageRequestController = null
    this.sending = false
    this.mediaRecorder = null
    this.activityTracker = null
    this.streamPanel = null
    this.activeTurnId = null
    this.lastSeq = 0
    this.turnFinalized = false
    this.imageGenerationWatchTimer = null
    this.imageGenerationWatchIndex = null
    this.unsubscribeCable = subscribeAgentChat((event) => this.receivedCable(event))
    this.renderMessages()
    this.renderMemoReferenceList()
    this.syncReferenceMemoImageButton()
    this.updateSendState()
    this.initialMessagesJsonTarget?.remove()
    this.initialMemoReferencesJsonTarget?.remove()
    this.resumeImageGenerationWatches()
    if (this.nyoyConfiguredValue && this.nyoyToolsUrlValue) {
      this.fetchNyoyTools()
    }
  }

  disconnect() {
    this.mediaRecorder?.state === "recording" && this.mediaRecorder.stop()
    if (this.memoSearchTimer) window.clearTimeout(this.memoSearchTimer)
    if (this.memoImageSearchTimer) window.clearTimeout(this.memoImageSearchTimer)
    this.memoImageRequestController?.abort()
    this.memoImageRequestController = null
    this.stopImageGenerationWatch()
    this.stopActivityTracker()
    this.unsubscribeCable?.()
    this.unsubscribeCable = null
  }

  async toggleRecording() {
    if (this.mediaRecorder?.state === "recording") return this.mediaRecorder.stop()
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) return this.setAudioStatus("このブラウザでは音声入力を利用できません。")
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      const chunks = []
      this.mediaRecorder = new MediaRecorder(stream)
      this.mediaRecorder.ondataavailable = (event) => event.data.size && chunks.push(event.data)
      this.mediaRecorder.onstop = () => this.transcribeRecording(new Blob(chunks, { type: this.mediaRecorder.mimeType || "audio/webm" }), stream)
      this.mediaRecorder.start()
      this.recordButtonTarget.setAttribute("aria-pressed", "true")
      this.setAudioStatus("録音中")
    } catch { this.setAudioStatus("マイクを利用できません。") }
  }

  async transcribeRecording(blob, stream) {
    stream.getTracks().forEach((track) => track.stop())
    this.recordButtonTarget.setAttribute("aria-pressed", "false")
    this.setAudioStatus("文字起こし中")
    const form = new FormData()
    form.append("file", blob, "recording.webm")
    form.append("authenticity_token", document.querySelector('meta[name="csrf-token"]')?.content || "")
    try {
      const res = await fetch(this.transcribeAudioUrlValue, { method: "POST", credentials: "same-origin", headers: csrfFetchHeaders(), body: form })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error)
      this.inputTarget.value = [this.inputTarget.value.trim(), data.text].filter(Boolean).join("\n")
      this.inputTarget.focus(); this.setAudioStatus("文字起こしを入力しました")
    } catch (error) { this.setAudioStatus(error.message || "文字起こしに失敗しました。") }
  }

  setAudioStatus(message) { if (this.hasAudioStatusTarget) this.audioStatusTarget.textContent = message }

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

  readInitialMemoReferences() {
    if (!this.hasInitialMemoReferencesJsonTarget) return []

    try {
      const raw = this.initialMemoReferencesJsonTarget.textContent?.trim()
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
      this.pruneUnavailableMcpTools()
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

  pruneUnavailableMcpTools() {
    if (!Array.isArray(this.enabledMcpTools) || this.nyoyTools.length === 0) return

    const available = new Set(this.nyoyTools.map((tool) => tool.name))
    const filtered = this.enabledMcpTools.filter((name) => available.has(name))
    if (filtered.length !== this.enabledMcpTools.length) {
      this.writeEnabledMcpTools(filtered)
    }
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

    const text = this.inputTarget?.value?.trim() || ""
    if (!text && this.pendingAttachments.length === 0 && this.pendingMemoReferences.length === 0) return

    const attachments = this.pendingAttachments.map((entry) => ({
      tsuzura_media_id: entry.tsuzura_media_id,
      filename: entry.filename
    }))
    const memoReferences = this.pendingMemoReferences.map((entry) => ({
      id: entry.id,
      title: entry.title
    }))

    this.clearError()
    this.clearAttachmentError()
    this.stopImageGenerationWatch()
    this.syncEnabledMcpTools()
    this.history.push({
      role: "user",
      content: text || (attachments.length > 0 ? "（画像を添付）" : "（参照メモについて回答）"),
      attachments,
      memo_references: memoReferences
    })
    if (this.inputTarget) this.inputTarget.value = ""
    this.pendingAttachments = []
    this.renderAttachmentList()
    this.renderMemoReferenceList()
    this.renderMessages()
    this.sending = true
    this.updateSendState()
    this.startActivityPanel()

    const turnId = crypto.randomUUID()
    this.activeTurnId = turnId
    this.lastSeq = 0
    this.turnFinalized = false

    try {
      const res = await fetch(this.chatUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: jsonRequestHeaders(),
        body: JSON.stringify(withAuthenticityToken({
          messages: this.history,
          conversation_id: this.conversationIdValue || null,
          turn_id: turnId,
          enabled_mcp_tools: this.enabledMcpTools,
          attachments,
          memo_reference_ids: memoReferences.map((entry) => entry.id)
        }))
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
        if (isCsrfErrorResponse(res.status, data)) {
          this.showError(data.error, { reload: true })
        } else {
          this.showError(data.error || "AI との通信に失敗しました。", {
            settingsUrl: data.settings_url
          })
        }
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
      activity: payload.trace || null,
      pending_tools: Boolean(payload.pending_tools),
      pending_tool_names: Array.isArray(payload.pending_tool_names)
        ? payload.pending_tool_names.map(String)
        : [],
      generated_images: Array.isArray(payload.mcp?.image_urls)
        ? payload.mcp.image_urls.map(String).filter(Boolean)
        : [],
      mcp_errors: Array.isArray(payload.mcp?.errors) ? payload.mcp.errors : [],
      image_generation_watch: payload.mcp?.image_generation_watch || null
    })

    if (
      (!payload.mcp?.image_urls || payload.mcp.image_urls.length === 0) &&
      payload.mcp?.image_generation_watch?.id
    ) {
      this.startImageGenerationWatch(payload.mcp.image_generation_watch, this.history.length - 1)
    }
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
        const url = new URL(this.chatUrlValue, window.location.origin)
        url.searchParams.set("conversation_id", this.conversationIdValue)
        const res = await fetch(url.toString(), {
          method: "DELETE",
          credentials: "same-origin",
          headers: {
            Accept: "application/json",
            ...csrfFetchHeaders()
          }
        })
        if (res.ok && this.hasNewChatUrlValue) {
          window.location.assign(this.newChatUrlValue)
          return
        }
      } catch {
        // ローカル表示は消す。サーバ削除失敗時も UI はリセットする。
      }
    }

    this.history = []
    this.conversationIdValue = ""
    this.pendingAttachments = []
    this.pendingMemoReferences = []
    this.renderAttachmentList()
    this.renderMemoReferenceList()
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
      if (Array.isArray(entry.attachments) && entry.attachments.length > 0) {
        bubble.append(document.createElement("br"))
        bubble.append(this.renderAttachmentPreview(entry.attachments))
      }
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

    if (!isUser && answerText.trim() && this.hasSynthesizeAudioUrlValue) {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "kb-toolbar-btn mt-1"
      button.setAttribute("aria-label", "回答を読み上げる")
      button.title = "読み上げ"
      button.textContent = "読み上げ"
      button.addEventListener("click", () => this.playSpeech(answerText, button))
      wrapper.append(button)
    }

    if (!isUser && entry.pending_tools) {
      wrapper.append(this.pendingToolsNoticeNode(entry))
    } else if (!isUser && Array.isArray(entry.mcp_errors) && entry.mcp_errors.length > 0) {
      wrapper.append(this.mcpErrorNoticeNode(entry.mcp_errors))
    }

    if (!isUser && Array.isArray(entry.generated_images) && entry.generated_images.length > 0) {
      wrapper.append(this.generatedImagesNode(entry.generated_images, entry))
    }

    return wrapper
  }

  async playSpeech(text, button) {
    button.disabled = true
    try {
      const res = await fetch(this.synthesizeAudioUrlValue, {
        method: "POST", credentials: "same-origin", headers: jsonRequestHeaders(),
        body: JSON.stringify(withAuthenticityToken({ text }))
      })
      if (!res.ok) throw new Error()
      const url = URL.createObjectURL(await res.blob())
      const audio = new Audio(url)
      audio.addEventListener("ended", () => URL.revokeObjectURL(url), { once: true })
      await audio.play()
    } catch { this.showError("音声再生に失敗しました。") } finally { button.disabled = false }
  }

  generatedImagesNode(urls, entry = {}) {
    const wrap = document.createElement("div")
    wrap.className = "kb-ai-chat-generated-images"

    const label = document.createElement("p")
    label.className = "kb-ai-chat-generated-images-label kb-text-muted"
    label.textContent = this.imageGenerationAwaitingSelection(entry) ? "ラフ案" : "生成画像"
    wrap.append(label)

    const grid = document.createElement("div")
    grid.className = "kb-ai-chat-generated-images-grid"

    urls.forEach((url, index) => {
      if (this.looksLikeImageUrl(url)) {
        const item = document.createElement("div")
        item.className = "kb-ai-chat-generated-image-item"

        const link = document.createElement("a")
        link.href = url
        link.target = "_blank"
        link.rel = "noopener noreferrer"
        link.className = "kb-ai-chat-generated-image-link"

        const img = document.createElement("img")
        img.src = url
        img.alt = "生成された画像"
        img.className = "kb-ai-chat-generated-image"
        img.loading = "lazy"
        link.append(img)
        item.append(link)

        if (this.imageGenerationAwaitingSelection(entry)) {
          item.append(this.refineDraftButton(entry, index))
        }

        grid.append(item)
      } else {
        const link = document.createElement("a")
        link.href = url
        link.target = "_blank"
        link.rel = "noopener noreferrer"
        link.className = "kb-chrome-btn-secondary kb-btn-xs"
        link.textContent = "如意でラフ案を見る"
        grid.append(link)
      }
    })

    wrap.append(grid)
    return wrap
  }

  imageGenerationAwaitingSelection(entry) {
    return String(entry?.image_generation_watch?.status || "").toLowerCase() === "awaiting_selection"
  }

  refineDraftButton(entry, draftIndex) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "kb-chrome-btn-primary kb-btn-xs kb-ai-chat-refine-button"
    button.textContent = "仕上げ"
    button.disabled = !entry?.image_generation_watch?.id || !this.hasRefineImageGenerationUrlTemplateValue
    button.addEventListener("click", () => this.refineImageDraft(entry, draftIndex))
    return button
  }

  async refineImageDraft(entry, draftIndex) {
    const generationId = entry?.image_generation_watch?.id
    if (!generationId || !this.hasRefineImageGenerationUrlTemplateValue) return

    const historyIndex = this.history.indexOf(entry)
    const url = this.refineImageGenerationUrlTemplateValue.replace(
      "__ID__",
      encodeURIComponent(String(generationId))
    )

    entry.image_generation_watch = {
      ...entry.image_generation_watch,
      status: "refining"
    }
    this.renderMessages()

    try {
      const res = await fetch(url, {
        method: "POST",
        credentials: "same-origin",
        headers: jsonRequestHeaders(),
        body: JSON.stringify(withAuthenticityToken({
          draft_index: draftIndex,
          conversation_id: this.conversationIdValue || null
        }))
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        this.showError(data.error || "画像の仕上げを開始できませんでした。")
        return
      }

      this.updateImageGenerationEntry(entry, data)
      if (!data.done || data.in_progress) {
        this.startImageGenerationWatch(
          entry.image_generation_watch || { id: generationId, status: data.status },
          historyIndex >= 0 ? historyIndex : null
        )
      }
    } catch {
      this.showError("画像の仕上げを開始できませんでした。")
    } finally {
      this.renderMessages()
    }
  }

  looksLikeImageUrl(url) {
    return /\.(png|jpe?g|gif|webp)(\?|$)/i.test(url) || url.includes("/rails/active_storage/")
  }

  startImageGenerationWatch(watch, historyIndex = null) {
    this.stopImageGenerationWatch()
    if (!watch?.id || !this.hasImageGenerationUrlTemplateValue) return

    this.imageGenerationWatchIndex =
      historyIndex != null ? historyIndex : this.history.length - 1

    const url = new URL(
      this.imageGenerationUrlTemplateValue.replace(
        "__ID__",
        encodeURIComponent(String(watch.id))
      ),
      window.location.origin
    )
    if (this.conversationIdValue) {
      url.searchParams.set("conversation_id", this.conversationIdValue)
    }
    let attempts = 0
    const maxAttempts = 100

    const poll = async () => {
      attempts += 1
      if (attempts > maxAttempts) {
        this.stopImageGenerationWatch()
        return
      }

      try {
        const res = await fetch(url.toString(), {
          credentials: "same-origin",
          headers: { Accept: "application/json" }
        })
        const data = await res.json().catch(() => ({}))
        if (!res.ok) return

        const urls = Array.isArray(data.image_urls)
          ? data.image_urls.map(String).filter(Boolean)
          : []
        if (urls.length > 0) {
          this.appendGeneratedImagesToAssistant(urls, data)
          this.stopImageGenerationWatch()
          return
        }

        if (data.done) {
          if (data.show_url) {
            this.appendGeneratedImagesToAssistant([ String(data.show_url) ])
          }
          this.stopImageGenerationWatch()
        }
      } catch {
        // 次のポーリングで再試行
      }
    }

    poll()
    this.imageGenerationWatchTimer = window.setInterval(poll, 3000)
  }

  stopImageGenerationWatch() {
    if (this.imageGenerationWatchTimer != null) {
      window.clearInterval(this.imageGenerationWatchTimer)
      this.imageGenerationWatchTimer = null
    }
    this.imageGenerationWatchIndex = null
  }

  resumeImageGenerationWatches() {
    let watchIndex = -1
    let watch = null

    this.history.forEach((entry, index) => {
      if (entry.role !== "assistant") return
      if (!entry.image_generation_watch?.id) return
      if (Array.isArray(entry.generated_images) && entry.generated_images.length > 0) return

      watchIndex = index
      watch = entry.image_generation_watch
    })

    if (watchIndex >= 0 && watch) {
      this.startImageGenerationWatch(watch, watchIndex)
    }
  }

  appendGeneratedImagesToAssistant(urls, data = {}) {
    const index = this.imageGenerationWatchIndex ?? this.history.length - 1
    const entry = this.history[index]
    if (!entry || entry.role !== "assistant") return

    this.updateImageGenerationEntry(entry, { ...data, image_urls: urls })
    this.renderMessages()
    this.focusLatestAnswer()
  }

  updateImageGenerationEntry(entry, data = {}) {
    if (!entry || entry.role !== "assistant") return

    const existing = Array.isArray(entry.generated_images) ? entry.generated_images : []
    const urls = Array.isArray(data.image_urls) ? data.image_urls.map(String).filter(Boolean) : []
    if (urls.length > 0) {
      const previousStatus = String(entry.image_generation_watch?.status || "").toLowerCase()
      const nextStatus = String(data.status || previousStatus).toLowerCase()
      const replaceDrafts = previousStatus === "awaiting_selection" && nextStatus !== "awaiting_selection"
      const base = replaceDrafts ? [] : existing

      entry.generated_images = [ ...base, ...urls ]
        .filter((value, idx, array) => array.indexOf(value) === idx)
    }

    const id = data.id || entry.image_generation_watch?.id
    if (id) {
      entry.image_generation_watch = {
        id,
        status: data.status || entry.image_generation_watch?.status,
        show_url: data.show_url || entry.image_generation_watch?.show_url
      }
    }
  }

  pendingToolsNoticeNode(entry) {
    const notice = document.createElement("div")
    notice.className = "kb-ai-chat-pending-tools"
    notice.setAttribute("role", "status")

    const title = document.createElement("p")
    title.className = "kb-ai-chat-pending-tools-title"
    title.textContent = "外部ツールは実行されませんでした"
    notice.append(title)

    const body = document.createElement("p")
    body.className = "kb-ai-chat-pending-tools-body"
    body.textContent = this.pendingToolsMessage(entry)
    notice.append(body)

    const actions = document.createElement("div")
    actions.className = "kb-ai-chat-pending-tools-actions"

    if (!this.nyoyConfiguredValue && this.hasNyoyMcpUrlValue) {
      const settingsLink = document.createElement("a")
      settingsLink.href = this.nyoyMcpUrlValue
      settingsLink.className = "kb-chrome-btn-secondary kb-btn-xs underline"
      settingsLink.textContent = "Nyoy MCP 設定を開く"
      actions.append(settingsLink)
    } else if (this.hasMcpToolsPanelTarget) {
      const openTools = document.createElement("button")
      openTools.type = "button"
      openTools.className = "kb-chrome-btn-secondary kb-btn-xs"
      openTools.textContent = "Nyoy MCP ツールを選ぶ"
      openTools.addEventListener("click", () => this.openMcpToolsPanel())
      actions.append(openTools)
    }

    if (actions.childElementCount > 0) {
      notice.append(actions)
    }

    return notice
  }

  pendingToolsMessage(entry) {
    const names = Array.isArray(entry.pending_tool_names) ? entry.pending_tool_names : []
    const labels = names.map((name) => this.constructor.pendingToolLabels[name] || name)
    const toolPart =
      labels.length > 0 ? `（${labels.join("、")}）` : ""

    if (!this.nyoyConfiguredValue) {
      return `この応答には Nyoy MCP 経由のツール${toolPart}が必要ですが、接続設定がありません。URL と API トークンを保存してください。`
    }

    if (names.includes("image_analysis")) {
      return `画像解析${toolPart}には画像の添付が必要です。ローカル添付または葛籠から選んでから再送信してください。`
    }

    if (names.includes("image_generation")) {
      return `画像生成${toolPart}は Nyoy 側の Stable Diffusion 接続が必要です。Nyoy MCP 設定と如意の sd.cpp 接続を確認してください。`
    }

    return `Nyoy MCP のツール${toolPart}が無効か、実行できませんでした。下の「Nyoy MCP ツール」で有効化するか、設定を確認してください。`
  }

  mcpErrorNoticeNode(errors) {
    const notice = document.createElement("div")
    notice.className = "kb-ai-chat-pending-tools"
    notice.setAttribute("role", "status")

    const title = document.createElement("p")
    title.className = "kb-ai-chat-pending-tools-title"
    title.textContent = "外部ツールの実行に失敗しました"
    notice.append(title)

    const list = document.createElement("ul")
    list.className = "kb-ai-chat-mcp-error-list"

    for (const entry of errors) {
      const item = document.createElement("li")
      const tool = entry?.tool || entry?.["tool"] || "tool"
      const message = entry?.message || entry?.["message"] || "不明なエラー"
      item.textContent = `${tool}: ${message}`
      list.append(item)
    }

    notice.append(list)
    return notice
  }

  openMcpToolsPanel() {
    if (!this.hasMcpToolsPanelTarget) return

    this.mcpToolsPanelTarget.open = true
    this.mcpToolsPanelTarget.scrollIntoView({ block: "nearest", behavior: "smooth" })

    if (this.nyoyTools.length === 0 && this.nyoyConfiguredValue && this.nyoyToolsUrlValue) {
      this.fetchNyoyTools()
    }
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

    if (options.reload) {
      this.errorTarget.append(" ")
      const reload = document.createElement("button")
      reload.type = "button"
      reload.className = "underline"
      reload.textContent = "再読み込み"
      reload.addEventListener("click", () => window.location.reload())
      this.errorTarget.append(reload)
    }

    this.errorTarget.classList.remove("hidden")
  }

  clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  async addFiles(event) {
    const files = Array.from(event.target.files || [])
    event.target.value = ""
    if (files.length === 0) return

    this.clearAttachmentError()
    for (const file of files) {
      try {
        const attachment = await this.uploadImageFile(file)
        this.pendingAttachments.push(attachment)
      } catch (error) {
        this.showAttachmentError(error.message || "画像のアップロードに失敗しました。")
      }
    }
    this.renderAttachmentList()
  }

  async uploadImageFile(file) {
    if (!this.uploadImageUrlValue) {
      throw new Error("画像アップロード URL が未設定です。")
    }

    const body = new FormData()
    body.append("file", file)

    const res = await fetch(this.uploadImageUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        ...csrfFetchHeaders()
      },
      body
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) {
      throw new Error(data.error || "画像のアップロードに失敗しました。")
    }

    const previewUrl = URL.createObjectURL(file)
    return {
      tsuzura_media_id: String(data.tsuzura_media_id || ""),
      filename: data.filename || file.name,
      preview_url: previewUrl
    }
  }

  renderAttachmentList() {
    if (!this.hasAttachmentListTarget) return

    this.attachmentListTarget.replaceChildren()
    if (this.pendingAttachments.length === 0) return

    for (const [index, attachment] of this.pendingAttachments.entries()) {
      this.attachmentListTarget.append(this.attachmentChipNode(attachment, index))
    }
  }

  attachmentChipNode(attachment, index) {
    const chip = document.createElement("div")
    chip.className =
      "inline-flex items-center gap-2 rounded-md border kb-border px-2 py-1 text-xs kb-text-primary"

    if (attachment.preview_url) {
      const img = document.createElement("img")
      img.src = attachment.preview_url
      img.alt = attachment.filename || "添付画像"
      img.className = "agent-chat-attachment-thumb"
      chip.append(img)
    }

    const label = document.createElement("span")
    label.className = "font-mono"
    label.textContent = attachment.filename || attachment.tsuzura_media_id
    chip.append(label)

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "kb-toolbar-btn px-1"
    remove.setAttribute("aria-label", "添付を削除")
    remove.textContent = "×"
    remove.addEventListener("click", () => {
      this.pendingAttachments.splice(index, 1)
      this.renderAttachmentList()
    })
    chip.append(remove)

    return chip
  }

  renderAttachmentPreview(attachments) {
    const wrap = document.createElement("div")
    wrap.className = "mt-2 flex flex-wrap gap-2"
    attachments.forEach((attachment) => {
      const chip = document.createElement("span")
      chip.className = "inline-block rounded border kb-border px-2 py-1 text-xs font-mono"
      chip.textContent = attachment.filename || attachment.tsuzura_media_id
      wrap.append(chip)
    })
    return wrap
  }

  async openMemoPicker(event) {
    event?.preventDefault()
    if (!this.hasMemoDialogTarget) return

    this.memoSelectedIds = new Set(this.pendingMemoReferences.map((entry) => String(entry.id)))
    this.memoDialogTarget.showModal()
    await this.loadMemoReferences("")
    this.memoSearchTarget?.focus()
  }

  closeMemoPicker(event) {
    event?.preventDefault()
    this.memoDialogTarget?.close()
  }

  searchMemos() {
    if (this.memoSearchTimer) window.clearTimeout(this.memoSearchTimer)
    this.memoSearchTimer = window.setTimeout(() => {
      void this.loadMemoReferences(this.memoSearchTarget?.value || "")
    }, 200)
  }

  async loadMemoReferences(query) {
    if (!this.memoReferencesUrlValue) return
    this.setMemoStatus("メモを読み込み中…")
    const url = new URL(this.memoReferencesUrlValue, window.location.origin)
    if (query.trim()) url.searchParams.set("q", query.trim())

    try {
      const res = await fetch(url.toString(), {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        this.setMemoStatus(data.error || "メモを取得できませんでした。")
        return
      }
      this.memoSearchResults = Array.isArray(data.memos) ? data.memos : []
      this.renderMemoResults()
      this.setMemoStatus(
        this.memoSearchResults.length > 0
          ? "参照するメモを5件まで選択できます。"
          : "該当するメモがありません。"
      )
    } catch {
      this.setMemoStatus("メモを取得できませんでした。")
    }
  }

  renderMemoResults() {
    if (!this.hasMemoResultsTarget) return
    this.memoResultsTarget.replaceChildren()

    for (const memo of this.memoSearchResults) {
      const row = document.createElement("label")
      row.className = "flex items-start gap-2 border-b kb-border px-3 py-2 text-sm kb-hover-row"
      const checkbox = document.createElement("input")
      checkbox.type = "checkbox"
      checkbox.value = String(memo.id)
      checkbox.checked = this.memoSelectedIds.has(String(memo.id))
      checkbox.disabled = !checkbox.checked && this.memoSelectedIds.size >= 5
      checkbox.addEventListener("change", () => {
        if (checkbox.checked) this.memoSelectedIds.add(checkbox.value)
        else this.memoSelectedIds.delete(checkbox.value)
        this.renderMemoResults()
        this.syncMemoConfirmButton()
      })
      const details = document.createElement("span")
      details.className = "min-w-0"
      const title = document.createElement("span")
      title.className = "block kb-text-primary"
      title.textContent = memo.title || "（無題）"
      const identity = document.createElement("span")
      identity.className = "mt-0.5 block text-xs kb-text-muted"
      identity.textContent = [memo.directory, this.formatMemoDate(memo.updated_at)].filter(Boolean).join(" · ")
      const excerpt = document.createElement("span")
      excerpt.className = "mt-1 block text-xs kb-text-muted"
      excerpt.textContent = memo.excerpt || "（本文なし）"
      details.append(title, identity, excerpt)
      row.append(checkbox, details)
      this.memoResultsTarget.append(row)
    }
    this.syncMemoConfirmButton()
  }

  syncMemoConfirmButton() {
    if (this.hasMemoConfirmButtonTarget) {
      this.memoConfirmButtonTarget.disabled = this.memoSelectedIds.size === 0
    }
  }

  confirmMemoSelection(event) {
    event?.preventDefault()
    const known = new Map([
      ...this.pendingMemoReferences,
      ...this.memoSearchResults
    ].map((entry) => [ String(entry.id), entry ]))
    this.pendingMemoReferences = [...this.memoSelectedIds]
      .map((id) => known.get(id))
      .filter(Boolean)
      .slice(0, 5)
    this.renderMemoReferenceList()
    this.closeMemoPicker()
    void this.persistMemoReferences()
  }

  renderMemoReferenceList() {
    if (!this.hasMemoReferenceListTarget) return
    this.memoReferenceListTarget.replaceChildren()
    if (this.hasMemoReferenceCountTarget) {
      this.memoReferenceCountTarget.textContent = `${this.pendingMemoReferences.length} / 5`
    }
    this.pendingMemoReferences.forEach((reference, index) => {
      const chip = document.createElement("div")
      chip.className = "inline-flex items-center gap-2 rounded-md border kb-border px-2 py-1 text-xs"
      const label = this.memoReferenceLabelNode(reference)
      const usage = document.createElement("span")
      usage.className = "kb-text-muted"
      usage.textContent = this.memoReferenceUsageLabel(reference, index)
      if (usage.textContent.includes("一部")) {
        usage.title = "参照上限により本文の一部だけをAIへ渡します"
      }
      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "kb-toolbar-btn px-1"
      remove.setAttribute("aria-label", "参照メモを削除")
      remove.textContent = "×"
      remove.addEventListener("click", () => {
        this.pendingMemoReferences.splice(index, 1)
        this.renderMemoReferenceList()
        void this.persistMemoReferences()
      })
      chip.append(label, usage, remove)
      this.memoReferenceListTarget.append(chip)
    })
    this.syncReferenceMemoImageButton()
  }

  memoReferenceLabelNode(reference) {
    const title = reference.title || "（無題）"
    const url = this.memoReferenceUrl(reference.id)
    if (!url) {
      const label = document.createElement("span")
      label.textContent = title
      return label
    }

    const link = document.createElement("a")
    link.href = url
    link.target = "_blank"
    link.rel = "noopener"
    link.className = "kb-inline-link"
    link.textContent = title
    link.title = "参照メモを新しいタブで開く"
    return link
  }

  memoReferenceUrl(id) {
    if (!id || !this.hasMemoUrlTemplateValue) return null
    return this.memoUrlTemplateValue.replace("__ID__", encodeURIComponent(String(id)))
  }

  memoReferenceUsageLabel(reference, index) {
    const total = Math.max(0, Number(reference.body_chars) || 0)
    const usedBefore = this.pendingMemoReferences
      .slice(0, index)
      .reduce((sum, entry) => sum + Math.min(Math.max(0, Number(entry.body_chars) || 0), 12000), 0)
    const remaining = Math.max(0, 30000 - usedBefore)
    const included = Math.min(total, 12000, remaining)
    const format = (value) => new Intl.NumberFormat("ja-JP").format(value)
    return included < total
      ? `${format(included)} / ${format(total)}文字・一部`
      : `${format(total)}文字`
  }

  async persistMemoReferences() {
    if (!this.conversationIdValue || !this.memoReferencesUrlValue) return

    const version = ++this.memoReferenceSyncVersion
    if (this.hasMemoReferenceListTarget) {
      this.memoReferenceListTarget.dataset.syncState = "pending"
    }
    try {
      const res = await fetch(this.memoReferencesUrlValue, {
        method: "PATCH",
        credentials: "same-origin",
        headers: jsonRequestHeaders(),
        body: JSON.stringify(withAuthenticityToken({
          conversation_id: this.conversationIdValue,
          memo_reference_ids: this.pendingMemoReferences.map((entry) => entry.id)
        }))
      })
      const data = await res.json().catch(() => ({}))
      if (version !== this.memoReferenceSyncVersion) return
      if (!res.ok) {
        this.setMemoReferenceSyncState("error")
        this.showError(data.error || "参照メモを保存できませんでした。")
        return
      }
      if (Array.isArray(data.memo_references)) {
        this.pendingMemoReferences = data.memo_references
        this.renderMemoReferenceList()
      }
      this.setMemoReferenceSyncState("complete")
    } catch {
      if (version === this.memoReferenceSyncVersion) {
        this.setMemoReferenceSyncState("error")
        this.showError("参照メモを保存できませんでした。")
      }
    }
  }

  setMemoReferenceSyncState(state) {
    if (this.hasMemoReferenceListTarget) {
      this.memoReferenceListTarget.dataset.syncState = state
    }
  }

  setMemoStatus(message) {
    if (this.hasMemoStatusTarget) this.memoStatusTarget.textContent = message
  }

  formatMemoDate(value) {
    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return ""
    return new Intl.DateTimeFormat("ja-JP", { dateStyle: "medium" }).format(date)
  }

  async openMemoImagePicker(event) {
    event?.preventDefault()
    await this.showMemoImagePicker({ referenceOnly: false })
  }

  async openReferenceMemoImagePicker(event) {
    event?.preventDefault()
    if (this.pendingMemoReferences.length === 0) {
      this.showAttachmentError("先に参照メモを選んでください。")
      return
    }
    await this.showMemoImagePicker({ referenceOnly: true })
  }

  async showMemoImagePicker({ referenceOnly }) {
    if (!this.hasMemoImageDialogTarget) return

    this.memoImageReferenceOnly = referenceOnly
    this.memoImageSelections = new Map()
    if (this.hasMemoImageDialogTitleTarget) {
      this.memoImageDialogTitleTarget.textContent = referenceOnly
        ? "参照メモの画像を選ぶ"
        : "メモの画像を選ぶ"
    }
    this.memoImageDialogTarget.showModal()
    await this.loadMemoImages("")
    this.memoImageSearchTarget?.focus()
  }

  closeMemoImagePicker(event) {
    event?.preventDefault()
    this.memoImageDialogTarget?.close()
  }

  searchMemoImages() {
    if (this.memoImageSearchTimer) window.clearTimeout(this.memoImageSearchTimer)
    this.memoImageSearchTimer = window.setTimeout(() => {
      void this.loadMemoImages(this.memoImageSearchTarget?.value || "")
    }, 200)
  }

  async loadMemoImages(query, { append = false } = {}) {
    if (!this.memoImagesUrlValue) return
    this.memoImageRequestController?.abort()
    const requestController = new AbortController()
    this.memoImageRequestController = requestController
    if (!append) {
      this.memoImageNextCursor = null
      this.syncMemoImageLoadMoreButton()
    }
    this.setMemoImageStatus("画像を読み込み中…")
    const url = new URL(this.memoImagesUrlValue, window.location.origin)
    if (query.trim()) url.searchParams.set("q", query.trim())
    if (append && this.memoImageNextCursor) {
      url.searchParams.set("cursor", this.memoImageNextCursor)
    }
    if (this.memoImageReferenceOnly) {
      url.searchParams.set(
        "memo_ids",
        this.pendingMemoReferences.map((reference) => reference.id).join(",")
      )
    }

    try {
      const res = await fetch(url.toString(), {
        credentials: "same-origin",
        headers: { Accept: "application/json" },
        signal: requestController.signal
      })
      const data = await res.json().catch(() => ({}))
      if (requestController !== this.memoImageRequestController) return
      if (!res.ok) throw new Error(data.error)
      const incoming = Array.isArray(data.images) ? data.images : []
      this.memoImageResults = append
        ? this.mergeMemoImageResults(this.memoImageResults, incoming)
        : incoming
      this.memoImageNextCursor = data.next_cursor || null
      this.renderMemoImageResults()
      this.syncMemoImageLoadMoreButton()
      if (this.memoImageSelections.size > 0) {
        this.updateMemoImageStatus()
      } else {
        this.setMemoImageStatus(
          this.memoImageResults.length ? "添付する画像を選んでください。" : "画像のあるメモが見つかりません。"
        )
      }
    } catch (error) {
      if (error?.name === "AbortError") return
      this.setMemoImageStatus("メモの画像を取得できませんでした。")
    } finally {
      if (requestController === this.memoImageRequestController) {
        this.memoImageRequestController = null
      }
    }
  }

  async loadMoreMemoImages(event) {
    event?.preventDefault()
    if (!this.memoImageNextCursor || !this.hasMemoImageLoadMoreButtonTarget) return

    this.memoImageLoadMoreButtonTarget.disabled = true
    await this.loadMemoImages(this.memoImageSearchTarget?.value || "", { append: true })
    if (this.hasMemoImageLoadMoreButtonTarget) {
      this.memoImageLoadMoreButtonTarget.disabled = false
    }
  }

  mergeMemoImageResults(current, incoming) {
    const byKey = new Map(current.map((image) => [this.memoImageKey(image), image]))
    incoming.forEach((image) => byKey.set(this.memoImageKey(image), image))
    return [...byKey.values()]
  }

  syncMemoImageLoadMoreButton() {
    if (!this.hasMemoImageLoadMoreWrapTarget) return

    const hasMore = Boolean(this.memoImageNextCursor)
    this.memoImageLoadMoreWrapTarget.classList.toggle("hidden", !hasMore)
    this.memoImageLoadMoreWrapTarget.classList.toggle("flex", hasMore)
  }

  renderMemoImageResults() {
    if (!this.hasMemoImageResultsTarget) return
    this.memoImageResultsTarget.replaceChildren()

    for (const image of this.memoImageResults) {
      const key = this.memoImageKey(image)
      const row = document.createElement("label")
      row.className = "flex items-center gap-3 border-b kb-border px-3 py-2 text-sm kb-hover-row"
      const checkbox = document.createElement("input")
      checkbox.type = "checkbox"
      checkbox.checked = this.memoImageSelections.has(key)
      checkbox.addEventListener("change", () => {
        if (checkbox.checked) this.memoImageSelections.set(key, image)
        else this.memoImageSelections.delete(key)
        this.syncMemoImageConfirmButton()
        this.updateMemoImageStatus()
      })
      const thumb = document.createElement("img")
      thumb.src = image.preview_url
      thumb.alt = ""
      thumb.loading = "lazy"
      thumb.className = "agent-chat-attachment-thumb"
      const details = document.createElement("span")
      details.className = "min-w-0"
      const filename = document.createElement("span")
      filename.className = "block truncate kb-text-primary"
      filename.textContent = image.filename
      const memo = document.createElement("span")
      memo.className = "mt-0.5 block truncate text-xs kb-text-muted"
      memo.textContent = [image.memo_title || "（無題）", image.directory].filter(Boolean).join(" · ")
      details.append(filename, memo)
      row.append(checkbox, thumb, details)
      this.memoImageResultsTarget.append(row)
    }
    this.syncMemoImageConfirmButton()
  }

  memoImageKey(image) {
    return `${image.memo_id}:${image.relative_path}`
  }

  syncMemoImageConfirmButton() {
    if (this.hasMemoImageConfirmButtonTarget) {
      this.memoImageConfirmButtonTarget.disabled = this.memoImageSelections.size === 0
    }
  }

  updateMemoImageStatus() {
    const count = this.memoImageSelections.size
    this.setMemoImageStatus(
      count > 0 ? `${count}件選択中です。検索条件を変えて追加できます。` : "添付する画像を選んでください。"
    )
  }

  async confirmMemoImageSelection(event) {
    event?.preventDefault()
    const selected = [...this.memoImageSelections.values()]
    if (selected.length === 0 || !this.uploadMemoImageUrlValue) return

    this.memoImageConfirmButtonTarget.disabled = true
    this.setMemoImageStatus("選択した画像を添付しています…")
    this.clearAttachmentError()
    const failedSelections = new Map()
    const errors = []
    let addedCount = 0
    for (const image of selected) {
      try {
        const res = await fetch(this.uploadMemoImageUrlValue, {
          method: "POST",
          credentials: "same-origin",
          headers: jsonRequestHeaders(),
          body: JSON.stringify(withAuthenticityToken({
            memo_id: image.memo_id,
            relative_path: image.relative_path
          }))
        })
        const data = await res.json().catch(() => ({}))
        if (!res.ok) throw new Error(data.error || "画像を添付できませんでした。")
        if (!this.pendingAttachments.some((entry) => entry.tsuzura_media_id === data.tsuzura_media_id)) {
          this.pendingAttachments.push(data)
        }
        addedCount += 1
      } catch (error) {
        failedSelections.set(this.memoImageKey(image), image)
        errors.push(error.message || "画像を添付できませんでした。")
      }
    }
    this.renderAttachmentList()
    this.memoImageSelections = failedSelections
    if (failedSelections.size > 0) {
      this.renderMemoImageResults()
      this.setMemoImageStatus(
        `${addedCount}件を添付し、${failedSelections.size}件に失敗しました。失敗した画像を再試行できます。`
      )
      this.showAttachmentError([...new Set(errors)].join(" / "))
      return
    }
    this.closeMemoImagePicker()
  }

  setMemoImageStatus(message) {
    if (this.hasMemoImageStatusTarget) this.memoImageStatusTarget.textContent = message
  }

  syncReferenceMemoImageButton() {
    if (!this.hasReferenceMemoImageButtonTarget) return

    const unavailable = this.pendingMemoReferences.length === 0
    this.referenceMemoImageButtonTarget.setAttribute("aria-disabled", String(unavailable))
    this.referenceMemoImageButtonTarget.title = unavailable
      ? "参照メモを選ぶと利用できます"
      : "参照中のメモにある画像から選びます"
  }

  async openTsuzuraPicker(event) {
    event?.preventDefault()
    if (!this.hasTsuzuraDialogTarget) return

    this.tsuzuraSelectedIds = new Set()
    if (this.hasTsuzuraConfirmButtonTarget) {
      this.tsuzuraConfirmButtonTarget.disabled = true
    }
    this.setTsuzuraStatus("アルバムを読み込み中…")
    this.tsuzuraAlbumListTarget?.replaceChildren()
    this.tsuzuraMediaListTarget?.replaceChildren()
    this.tsuzuraDialogTarget.showModal()
    await this.loadTsuzuraAlbums()
  }

  closeTsuzuraPicker(event) {
    event?.preventDefault()
    this.tsuzuraDialogTarget?.close()
  }

  async loadTsuzuraAlbums() {
    if (!this.tsuzuraAlbumsUrlValue) {
      this.setTsuzuraStatus("葛籠 API が未設定です。")
      return
    }

    try {
      const res = await fetch(this.tsuzuraAlbumsUrlValue, {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        this.setTsuzuraStatus(data.error || "アルバム一覧の取得に失敗しました。")
        return
      }

      this.renderTsuzuraAlbums(data.albums || [])
      this.setTsuzuraStatus(
        (data.albums || []).length ? "アルバムを選んでください。" : "アルバムがありません。"
      )
    } catch {
      this.setTsuzuraStatus("アルバム一覧の取得に失敗しました。")
    }
  }

  renderTsuzuraAlbums(albums) {
    if (!this.hasTsuzuraAlbumListTarget) return

    this.tsuzuraAlbumListTarget.replaceChildren()
    for (const album of albums) {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "block w-full border-b kb-border px-3 py-2 text-left text-sm kb-hover-row"
      button.textContent = `${album.title || "（無題）"} · ${album.media_item_count ?? "?"} 枚`
      button.addEventListener("click", () => this.loadTsuzuraAlbum(album.id))
      this.tsuzuraAlbumListTarget.append(button)
    }
  }

  async loadTsuzuraAlbum(albumId) {
    if (!this.tsuzuraAlbumUrlTemplateValue) return

    const url = this.tsuzuraAlbumUrlTemplateValue.replace(
      "__ID__",
      encodeURIComponent(String(albumId))
    )
    this.setTsuzuraStatus("写真を読み込み中…")

    try {
      const res = await fetch(url, {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        this.setTsuzuraStatus("アルバムを開けませんでした。")
        return
      }

      this.renderTsuzuraMedia(data)
      this.setTsuzuraStatus("添付する写真を選んでください。")
    } catch {
      this.setTsuzuraStatus("写真の読み込みに失敗しました。")
    }
  }

  renderTsuzuraMedia(album) {
    if (!this.hasTsuzuraMediaListTarget) return

    const ids = Array.isArray(album.media_item_ids)
      ? album.media_item_ids.map((id) => String(id).toUpperCase())
      : []
    this.tsuzuraMediaListTarget.replaceChildren()

    if (ids.length === 0) {
      const empty = document.createElement("p")
      empty.className = "px-3 py-2 text-xs kb-text-muted"
      empty.textContent = "写真がありません。"
      this.tsuzuraMediaListTarget.append(empty)
      return
    }

    for (const id of ids) {
      const row = document.createElement("label")
      row.className = "flex items-center gap-2 border-b kb-border px-3 py-2 text-xs"

      const checkbox = document.createElement("input")
      checkbox.type = "checkbox"
      checkbox.value = id
      checkbox.addEventListener("change", () => this.syncTsuzuraSelection())

      const text = document.createElement("span")
      text.className = "font-mono"
      text.textContent = id

      row.append(checkbox, text)
      this.tsuzuraMediaListTarget.append(row)
    }
  }

  syncTsuzuraSelection() {
    if (!this.hasTsuzuraMediaListTarget) return

    this.tsuzuraSelectedIds = new Set(
      [...this.tsuzuraMediaListTarget.querySelectorAll('input[type="checkbox"]:checked')].map(
        (input) => input.value
      )
    )
    if (this.hasTsuzuraConfirmButtonTarget) {
      this.tsuzuraConfirmButtonTarget.disabled = this.tsuzuraSelectedIds.size === 0
    }
  }

  confirmTsuzuraSelection(event) {
    event?.preventDefault()
    for (const id of this.tsuzuraSelectedIds) {
      if (this.pendingAttachments.some((entry) => entry.tsuzura_media_id === id)) continue
      this.pendingAttachments.push({
        tsuzura_media_id: id,
        filename: id.slice(-8)
      })
    }
    this.renderAttachmentList()
    this.closeTsuzuraPicker()
  }

  setTsuzuraStatus(message) {
    if (!this.hasTsuzuraStatusTarget) return
    this.tsuzuraStatusTarget.textContent = message
  }

  showAttachmentError(message) {
    if (!this.hasAttachmentErrorTarget) return
    this.attachmentErrorTarget.textContent = message
    this.attachmentErrorTarget.classList.remove("hidden")
  }

  clearAttachmentError() {
    if (!this.hasAttachmentErrorTarget) return
    this.attachmentErrorTarget.textContent = ""
    this.attachmentErrorTarget.classList.add("hidden")
  }
}
