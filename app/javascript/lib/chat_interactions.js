// AI チャットのモデル・ツールとのやり取りログ（ActionCable イベント反映）。

const ROLE_LABELS = {
  request: "リクエスト",
  response: "応答",
  thinking: "思考",
  tool: "ツール"
}

export class ChatStreamPanel {
  constructor() {
    this.root = document.createElement("div")
    this.root.className = "kb-ai-chat-activity kb-ai-chat-activity-running"

    const header = document.createElement("div")
    header.className = "kb-ai-chat-activity-header"

    const title = document.createElement("span")
    title.className = "kb-ai-chat-activity-title"
    title.textContent = "処理中…"

    this.elapsedEl = document.createElement("span")
    this.elapsedEl.className = "kb-ai-chat-activity-elapsed kb-text-muted"
    this.elapsedEl.dataset.chatActivityElapsed = "true"
    this.elapsedEl.textContent = "0.0秒"

    header.append(title, this.elapsedEl)

    this.stepsEl = document.createElement("ol")
    this.stepsEl.className = "kb-ai-chat-steps"

    this.interactionsEl = document.createElement("div")
    this.interactionsEl.className = "kb-ai-chat-interactions"

    this.previewEl = document.createElement("pre")
    this.previewEl.className = "kb-ai-chat-live-preview hidden"
    this.previewEl.dataset.chatLivePreview = "true"

    this.root.append(header, this.stepsEl, this.interactionsEl, this.previewEl)

    this.steps = new Map()
    this.interactionNodes = new Map()
    this.previewText = ""
  }

  element() {
    return this.root
  }

  setElapsed(ms) {
    this.elapsedEl.textContent = `${(ms / 1000).toFixed(1)}秒`
  }

  upsertTraceStep(step, phase) {
    if (!step?.key) return

    const status = phase === "completed" ? "completed" : "running"
    this.steps.set(step.key, { ...step, status })
    this.renderSteps()
  }

  appendInteraction(event) {
    const key = `${event.step_key}:${event.role}:${event.model || ""}`
    let node = this.interactionNodes.get(key)

    if (!node || !event.append) {
      node = this.createInteractionNode(event)
      this.interactionsEl.append(node)
      this.interactionNodes.set(key, node)
      return
    }

    const body = node.querySelector(".kb-ai-chat-interaction-body")
    if (body) body.textContent += event.text || ""
  }

  appendAssistantDelta(text, { thinking = false } = {}) {
    const chunk = String(text ?? "")
    if (!chunk) return

    if (thinking) {
      const key = "assistant:thinking"
      let node = this.interactionNodes.get(key)
      if (!node) {
        node = this.createInteractionNode({
          step_key: "assistant",
          role: "thinking",
          model: null,
          text: chunk
        })
        this.interactionsEl.append(node)
        this.interactionNodes.set(key, node)
      } else {
        const body = node.querySelector(".kb-ai-chat-interaction-body")
        if (body) body.textContent += chunk
      }
      return
    }

    this.previewEl.classList.remove("hidden")
    this.previewText += chunk
    this.previewEl.textContent = this.previewText
  }

  renderSteps() {
    this.stepsEl.replaceChildren()
    for (const step of this.steps.values()) {
      const li = document.createElement("li")
      li.className = `kb-ai-chat-step kb-ai-chat-step-${step.status || "pending"}`

      const head = document.createElement("div")
      head.className = "kb-ai-chat-step-head"

      const label = document.createElement("span")
      label.className = "kb-ai-chat-step-label"
      label.textContent = step.label || step.key

      const state = document.createElement("span")
      state.className = "kb-ai-chat-step-state"
      if (step.status === "completed" && step.elapsed_ms != null) {
        state.textContent = `${(step.elapsed_ms / 1000).toFixed(1)}秒`
      } else if (step.status === "running") {
        state.textContent = "処理中"
      } else {
        state.textContent = step.detail || ""
      }

      head.append(label, state)
      li.append(head)

      if (step.detail && step.status === "completed") {
        const detail = document.createElement("div")
        detail.className = "kb-ai-chat-step-detail"
        detail.textContent = step.detail
        li.append(detail)
      }

      this.stepsEl.append(li)
    }
  }

  createInteractionNode(event) {
    const item = document.createElement("details")
    item.className = "kb-ai-chat-interaction"
    item.open = event.role === "response" || event.role === "thinking"

    const summary = document.createElement("summary")
    summary.className = "kb-ai-chat-interaction-summary"

    const role = document.createElement("span")
    role.className = "kb-ai-chat-interaction-role"
    role.textContent = ROLE_LABELS[event.role] || event.role

    const meta = document.createElement("span")
    meta.className = "kb-ai-chat-interaction-meta kb-text-muted"
    meta.textContent = [event.step_key, event.model].filter(Boolean).join(" · ")

    summary.append(role, meta)

    const body = document.createElement("pre")
    body.className = "kb-ai-chat-interaction-body"
    body.textContent = event.text || ""

    item.append(summary, body)
    return item
  }
}

export function buildInteractionLog(interactions) {
  const container = document.createElement("div")
  container.className = "kb-ai-chat-interactions"

  for (const entry of interactions || []) {
    const panel = new ChatStreamPanel()
    container.append(panel.createInteractionNode(entry))
  }

  return container
}
