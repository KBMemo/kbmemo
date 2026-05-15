import { Controller } from "@hotwired/stimulus"

// 画面上部へ Rails flash と同様の一時 notice を表示する
export default class extends Controller {
  static targets = ["live"]

  connect() {
    this._onShow = (event) => {
      this.present(event.detail?.message)
    }
    document.addEventListener("flash-notice:show", this._onShow)
  }

  disconnect() {
    document.removeEventListener("flash-notice:show", this._onShow)
  }

  present(message) {
    if (!message) return

    const el = document.createElement("p")
    el.className =
      "mb-4 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-900"
    el.setAttribute("role", "status")
    el.textContent = message

    const container = this.hasLiveTarget ? this.liveTarget : this.element
    container.prepend(el)

    window.setTimeout(() => {
      el.remove()
    }, 6000)
  }
}
