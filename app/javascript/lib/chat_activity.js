// AI チャットのタスク進行・経過時間表示（Nyoy の stats / tool 表示を参考）。

export function formatChatDuration(seconds) {
  if (seconds == null || Number.isNaN(seconds)) return "—"
  if (seconds < 60) return `${seconds.toFixed(1)}秒`
  const minutes = Math.floor(seconds / 60)
  const remainder = seconds % 60
  return `${minutes}分${Math.round(remainder)}秒`
}

export function formatChatDurationMs(ms) {
  if (ms == null || Number.isNaN(ms)) return "—"
  return formatChatDuration(ms / 1000)
}

const STATUS_LABELS = {
  pending: "待機",
  running: "処理中",
  completed: "完了",
  error: "失敗"
}

export function buildChatStats(stats) {
  const dl = document.createElement("dl")
  dl.className = "kb-ai-chat-stats"

  for (const stat of stats || []) {
    if (!stat?.label) continue
    const item = document.createElement("div")
    item.className = "kb-ai-chat-stat"

    const dt = document.createElement("dt")
    dt.textContent = stat.label

    const dd = document.createElement("dd")
    dd.textContent = stat.value ?? "—"

    item.append(dt, dd)
    dl.append(item)
  }

  return dl
}

export function buildChatSteps(steps, { running = false } = {}) {
  const list = document.createElement("ol")
  list.className = "kb-ai-chat-steps"

  const items = steps?.length
    ? steps
    : defaultPendingSteps()

  for (const step of items) {
    const li = document.createElement("li")
    const status = running && step.status === "running" ? "running" : step.status || "pending"
    li.className = `kb-ai-chat-step kb-ai-chat-step-${status}`

    const head = document.createElement("div")
    head.className = "kb-ai-chat-step-head"

    const label = document.createElement("span")
    label.className = "kb-ai-chat-step-label"
    label.textContent = step.label || step.key || "タスク"

    const state = document.createElement("span")
    state.className = "kb-ai-chat-step-state"
    if (status === "completed" && step.elapsed_ms != null) {
      state.textContent = formatChatDurationMs(step.elapsed_ms)
    } else {
      state.textContent = STATUS_LABELS[status] || status
    }

    head.append(label, state)

    const detail = document.createElement("div")
    detail.className = "kb-ai-chat-step-detail"
    if (step.detail) detail.textContent = step.detail

    li.append(head)
    if (step.detail) li.append(detail)
    list.append(li)
  }

  return list
}

function defaultPendingSteps() {
  return [
    { key: "intent", label: "Intent 分類", status: "running" },
    { key: "rag_search", label: "メモ検索（RAG）", status: "pending" },
    { key: "mcp_tools", label: "外部ツール（Nyoy MCP）", status: "pending" },
    { key: "generate", label: "応答生成", status: "pending" }
  ]
}

export function buildChatActivity({ trace, running = false, elapsedMs = null }) {
  const panel = document.createElement("div")
  panel.className = `kb-ai-chat-activity${running ? " kb-ai-chat-activity-running" : ""}`

  const header = document.createElement("div")
  header.className = "kb-ai-chat-activity-header"

  const title = document.createElement("span")
  title.className = "kb-ai-chat-activity-title"
  title.textContent = running ? "処理中…" : "タスク"

  const elapsed = document.createElement("span")
  elapsed.className = "kb-ai-chat-activity-elapsed kb-text-muted"
  elapsed.dataset.chatActivityElapsed = "true"
  const totalMs = running ? elapsedMs : trace?.total_elapsed_ms
  elapsed.textContent = formatChatDurationMs(totalMs)

  header.append(title, elapsed)
  panel.append(header)

  if (!running && trace?.stats?.length) {
    panel.append(buildChatStats(trace.stats))
  }

  const steps = buildChatSteps(trace?.steps, { running })
  panel.append(steps)

  return panel
}

export class ChatActivityTracker {
  constructor({ onTick }) {
    this.onTick = onTick
    this.startedAt = performance.now()
    this.timer = null
  }

  start() {
    this.stop()
    this.startedAt = performance.now()
    this.timer = window.setInterval(() => {
      this.onTick?.(Math.round(performance.now() - this.startedAt))
    }, 100)
    this.onTick?.(0)
  }

  stop() {
    if (this.timer != null) {
      window.clearInterval(this.timer)
      this.timer = null
    }
  }
}
