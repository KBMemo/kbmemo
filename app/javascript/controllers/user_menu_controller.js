import { Controller } from "@hotwired/stimulus"
import {
  applyTheme,
  getStoredThemeId,
  populateThemeSelect,
} from "../theme/theme.js"

// ヘッダー: 表示名ボタンで開く個人メニュー（外クリック・Escape で閉じる）
export default class extends Controller {
  static targets = ["panel", "button", "themeSelect"]

  connect() {
    if (this.hasThemeSelectTarget) {
      populateThemeSelect(this.themeSelectTarget)
      this.themeSelectTarget.value = getStoredThemeId()
    }
  }

  changeTheme() {
    if (!this.hasThemeSelectTarget) return
    applyTheme(this.themeSelectTarget.value)
  }

  disconnect() {
    this.teardownDocumentListeners()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this.isOpen()) {
      this.hide()
    } else {
      this.show()
    }
  }

  isOpen() {
    return !this.panelTarget.classList.contains("hidden")
  }

  show() {
    this.panelTarget.classList.remove("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this._outside = (e) => {
      if (!this.element.contains(e.target)) this.hide()
    }
    this._escape = (e) => {
      if (e.key === "Escape") this.hide()
    }
    queueMicrotask(() => {
      document.addEventListener("click", this._outside)
    })
    document.addEventListener("keydown", this._escape)
  }

  hide() {
    this.panelTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.teardownDocumentListeners()
  }

  teardownDocumentListeners() {
    if (this._outside) {
      document.removeEventListener("click", this._outside)
      this._outside = null
    }
    if (this._escape) {
      document.removeEventListener("keydown", this._escape)
      this._escape = null
    }
  }
}
