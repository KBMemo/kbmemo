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
    this.panelTarget.id ||= `user-menu-panel-${Math.random().toString(36).slice(2)}`
    this.buttonTarget.setAttribute("aria-controls", this.panelTarget.id)

    this._closeOtherMenus = (event) => {
      if (event.detail?.source === this.element) return
      this.hide()
    }
    document.addEventListener("user-menu:close", this._closeOtherMenus)

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
    document.removeEventListener("user-menu:close", this._closeOtherMenus)
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
    document.dispatchEvent(new CustomEvent("user-menu:close", { detail: { source: this.element } }))
    this.panelTarget.classList.remove("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this._outside = (e) => {
      if (!this.element.contains(e.target)) this.hide()
    }
    this._escape = (e) => {
      if (e.key === "Escape") {
        e.preventDefault()
        this.hide({ restoreFocus: true })
      }
    }
    this._menuKeys = (e) => {
      this.handleMenuKeydown(e)
    }
    queueMicrotask(() => {
      document.addEventListener("click", this._outside)
      this.firstMenuItem()?.focus()
    })
    document.addEventListener("keydown", this._escape)
    this.panelTarget.addEventListener("keydown", this._menuKeys)
  }

  hide({ restoreFocus = false } = {}) {
    const wasOpen = this.isOpen()
    this.panelTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.teardownDocumentListeners()
    if (restoreFocus && wasOpen) this.buttonTarget.focus()
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
    if (this._menuKeys) {
      this.panelTarget.removeEventListener("keydown", this._menuKeys)
      this._menuKeys = null
    }
  }

  handleMenuKeydown(event) {
    if (event.key === "Tab") return

    const items = this.menuItems()
    if (items.length === 0) return

    const currentIndex = items.indexOf(document.activeElement)
    let nextIndex = null

    switch (event.key) {
      case "ArrowDown":
        nextIndex = currentIndex >= 0 ? (currentIndex + 1) % items.length : 0
        break
      case "ArrowUp":
        nextIndex = currentIndex >= 0 ? (currentIndex - 1 + items.length) % items.length : items.length - 1
        break
      case "Home":
        nextIndex = 0
        break
      case "End":
        nextIndex = items.length - 1
        break
      default:
        return
    }

    event.preventDefault()
    items[nextIndex].focus()
  }

  firstMenuItem() {
    return this.menuItems()[0] ?? null
  }

  menuItems() {
    return [
      ...this.panelTarget.querySelectorAll(
        `a[role="menuitem"], button[role="menuitem"]:not([disabled])`
      ),
    ].filter((el) => el.offsetParent !== null)
  }
}
