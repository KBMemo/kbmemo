import { Controller } from "@hotwired/stimulus"
import {
  applyTheme,
  getStoredThemeId,
  populateThemeSelect,
} from "../theme/theme.js"
import {
  applySkin,
  getStoredSkinId,
  populateSkinSelect,
} from "../theme/memo_skins.js"

// ヘッダー: 表示名ボタンで開く個人メニュー（外クリック・Escape で閉じる）
export default class extends Controller {
  static targets = ["panel", "button", "themeSelect", "skinSelect"]

  connect() {
    if (this.hasThemeSelectTarget) {
      populateThemeSelect(this.themeSelectTarget)
      this.themeSelectTarget.value = getStoredThemeId()
    }
    if (this.hasSkinSelectTarget) {
      populateSkinSelect(this.skinSelectTarget)
      this.skinSelectTarget.value = getStoredSkinId()
    }
  }

  changeTheme() {
    if (!this.hasThemeSelectTarget) return
    applyTheme(this.themeSelectTarget.value)
  }

  changeSkin() {
    if (!this.hasSkinSelectTarget) return
    applySkin(this.skinSelectTarget.value)
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
