// AI チャットのモデル・ツールとのやり取りログ（ActionCable イベント反映）。

const ROLE_LABELS = {
  request: "リクエスト",
  response: "応答",
  thinking: "思考",
  tool: "ツール"
}

const GENERATE_STEP_KEYS = new Set(["generate", "generate_escalated"])

/** @param {Array<{ role?: string, step_key?: string, text?: string }> | undefined} interactions */
export function replyFromTraceInteractions(interactions) {
  if (!Array.isArray(interactions) || interactions.length === 0) return ""

  const responses = interactions.filter((entry) => entry.role === "response")
  const generateResponses = responses.filter((entry) =>
    GENERATE_STEP_KEYS.has(String(entry.step_key || ""))
  )
  const chosen = (generateResponses.length > 0 ? generateResponses : responses).at(-1)
  return String(chosen?.text ?? "")
}

/** @param {{ reply?: string, trace?: { interactions?: Array }, streamedPreview?: string }} sources */
export function resolveAssistantReply({ reply, trace, streamedPreview = "" }) {
  const direct = String(reply ?? "")
  if (direct.trim()) return direct

  const fromTrace = replyFromTraceInteractions(trace?.interactions)
  if (fromTrace.trim()) return fromTrace

  return String(streamedPreview ?? "")
}

const FOLLOW_ROLES = new Set(["thinking", "response"])

export function scrollInteractionBodyToEnd(body, { intoView = false } = {}) {
  if (!body) return

  body.scrollTop = body.scrollHeight

  if (!intoView) return

  requestAnimationFrame(() => {
    body.scrollIntoView({ block: "nearest", behavior: "instant" })
  })
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

    this.root.append(header, this.stepsEl, this.interactionsEl)

    this.steps = new Map()
    this.interactionNodes = new Map()
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

    if (!node) {
      node = this.createInteractionNode(event)
      this.interactionsEl.append(node)
      this.interactionNodes.set(key, node)
      this.followInteraction(event.role, node)
      return
    }

    const body = node.querySelector(".kb-ai-chat-interaction-body")
    if (!body) return

    if (event.append) {
      body.textContent += event.text || ""
    } else {
      body.textContent = event.text || ""
    }

    this.followInteraction(event.role, node)
  }

  followInteraction(role, node) {
    if (!FOLLOW_ROLES.has(role)) return

    const body = node.querySelector(".kb-ai-chat-interaction-body")
    scrollInteractionBodyToEnd(body, { intoView: role === "response" })
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
      } else if (step.status === "error" || step.status === "skipped") {
        state.textContent = step.detail || step.status
      } else {
        state.textContent = step.detail || ""
      }

      head.append(label, state)
      li.append(head)

      if (step.detail && (step.status === "completed" || step.status === "error" || step.status === "skipped")) {
        const detail = document.createElement("div")
        detail.className = "kb-ai-chat-step-detail"
        detail.textContent = step.detail
        li.append(detail)
      }

      this.stepsEl.append(li)
    }
  }

  createInteractionNode(event, { expanded = null } = {}) {
    const item = document.createElement("details")
    item.className = "kb-ai-chat-interaction"
    item.open =
      expanded ??
      (event.role === "response" || event.role === "thinking" || event.role === "request")

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
    if (FOLLOW_ROLES.has(event.role)) {
      body.classList.add("kb-ai-chat-interaction-body-follow")
      body.dataset.controller = "interaction-autoscroll"
      if (event.role === "response") {
        body.dataset.interactionAutoscrollIntoViewValue = "true"
      }
    }
    body.textContent = event.text || ""

    item.append(summary, body)
    return item
  }
}

export function buildInteractionLog(interactions, { expanded = false } = {}) {
  const container = document.createElement("div")
  container.className = "kb-ai-chat-interactions"

  const panel = new ChatStreamPanel()
  for (const entry of interactions || []) {
    container.append(panel.createInteractionNode(entry, { expanded }))
  }

  return container
}
