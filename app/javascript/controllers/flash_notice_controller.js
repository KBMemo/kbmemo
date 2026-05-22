import { Controller } from "@hotwired/stimulus"

const TOAST_BASE =
  "pointer-events-auto flex items-start gap-2 rounded-md border px-3 py-2 text-sm shadow-md transition-all duration-200 ease-out"
const DISMISS_BASE =
  "shrink-0 rounded p-0.5 text-base leading-none opacity-60 hover:opacity-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-1"

// 画面上部へ Rails flash と同様の一時 notice を表示する（固定トースト）
export default class extends Controller {
  static targets = ["live", "message"]

  static values = {
    dismissAfter: { type: Number, default: 6000 }
  }

  connect() {
    this._onShow = (event) => {
      this.present(event.detail?.message, event.detail?.level)
    }
    document.addEventListener("flash-notice:show", this._onShow)
    this.messageTargets.forEach((el) => this.arm(el))
  }

  disconnect() {
    document.removeEventListener("flash-notice:show", this._onShow)
    this.messageTargets.forEach((el) => this.clearTimer(el))
  }

  dismiss(event) {
    event.preventDefault()
    const el = event.currentTarget.closest("[data-flash-notice-target='message']")
    if (el) this.removeMessage(el)
  }

  present(message, level = "notice") {
    if (!message) return

    const el = this.buildElement(message, level)
    const container = this.liveContainer()
    container.prepend(el)
    this.showElement(el)
    this.arm(el)
  }

  liveContainer() {
    if (this.hasLiveTarget) return this.liveTarget

    const container = document.createElement("div")
    container.id = "flash-live"
    container.dataset.flashNoticeTarget = "live"
    container.setAttribute("aria-live", "polite")
    container.className =
      "pointer-events-none fixed top-4 right-4 z-50 flex w-[min(100%-2rem,24rem)] flex-col gap-2"
    this.element.appendChild(container)
    return container
  }

  buildElement(message, level) {
    const el = document.createElement("div")
    el.className = `${this.messageClasses(level)} opacity-0 translate-y-2`
    el.setAttribute("role", "status")
    el.dataset.flashNoticeTarget = "message"

    const text = document.createElement("span")
    text.className = "min-w-0 flex-1"
    text.textContent = message

    const button = document.createElement("button")
    button.type = "button"
    button.className = this.dismissButtonClasses(level)
    button.setAttribute("aria-label", "メッセージを閉じる")
    button.dataset.action = "flash-notice#dismiss"
    button.textContent = "×"

    el.appendChild(text)
    el.appendChild(button)
    return el
  }

  messageClasses(level) {
    if (String(level) === "notice") {
      return `${TOAST_BASE} border-emerald-200 bg-emerald-50 text-emerald-900`
    }
    return `${TOAST_BASE} border-amber-200 bg-amber-50 text-amber-900`
  }

  dismissButtonClasses(level) {
    if (String(level) === "notice") {
      return `${DISMISS_BASE} focus-visible:ring-emerald-400`
    }
    return `${DISMISS_BASE} focus-visible:ring-amber-400`
  }

  showElement(el) {
    requestAnimationFrame(() => {
      el.classList.remove("opacity-0", "translate-y-2")
    })
  }

  arm(el) {
    this.clearTimer(el)
    el._flashDismissTimer = window.setTimeout(() => {
      this.removeMessage(el)
    }, this.dismissAfterValue)
  }

  clearTimer(el) {
    if (!el?._flashDismissTimer) return
    window.clearTimeout(el._flashDismissTimer)
    el._flashDismissTimer = null
  }

  removeMessage(el) {
    this.clearTimer(el)
    el.classList.add("opacity-0", "translate-x-2", "pointer-events-none")
    window.setTimeout(() => el.remove(), 200)
  }
}
