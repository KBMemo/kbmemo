import { Controller } from "@hotwired/stimulus"

const COPY_SHORTCUT = typeof navigator !== "undefined" && /Mac|iPhone|iPad/.test(navigator.platform)
  ? "⌘C"
  : "Ctrl+C"

/** @typedef {{ label?: string, separator?: boolean, disabled?: boolean, shortcut?: string, action?: () => void | Promise<void> }} MenuItem */

export default class extends Controller {
  static values = {
    editUrl: String,
    canEdit: Boolean,
    hasBacklinks: Boolean,
    backlinksAnchor: String,
  }

  connect() {
    this.menuEl = null
    this.boundHide = this.hide.bind(this)
  }

  disconnect() {
    this.hide()
    this.removeGlobalListeners()
    this.menuEl?.remove()
    this.menuEl = null
  }

  open(event) {
    if (this.shouldIgnore(event)) return

    event.preventDefault()
    event.stopPropagation()
    this.hide()

    const image = this.imageFromEvent(event)
    const selected = this.selectedText()
    this.showMenu(event.clientX, event.clientY, this.buildMenuItems({ selected, image }))
    this.addGlobalListeners()
  }

  /** @param {Event} event */
  shouldIgnore(event) {
    const target = event.target
    if (!(target instanceof Element)) return false
    if (target.closest("a, button, input, textarea, select, label, .memo-show-context-menu")) return true
    return false
  }

  /** @param {Event} event @returns {HTMLImageElement | null} */
  imageFromEvent(event) {
    const target = event.target
    if (!(target instanceof Element)) return null

    const img = target.closest(".memo-body img")
    if (!(img instanceof HTMLImageElement)) return null
    if (!img.src) return null

    return img
  }

  /** @param {{ selected: string, image: HTMLImageElement | null }} options */
  buildMenuItems({ selected, image }) {
    /** @type {MenuItem[]} */
    const items = []

    if (image) {
      items.push({
        label: "画像をダウンロード",
        action: () => this.downloadImage(image),
      })
      items.push({ separator: true })
    }

    items.push(
      {
        label: "選択テキストをコピー",
        disabled: !selected,
        shortcut: COPY_SHORTCUT,
        action: () => this.copySelection(selected),
      },
      { separator: true },
      {
        label: "メモの先頭へ",
        action: () => this.scrollToTop(),
      },
    )

    if (this.canEditValue) {
      items.push({
        label: "このメモを編集",
        action: () => {
          const navigate = window.Turbo?.visit ?? ((url) => window.location.assign(url))
          navigate(this.editUrlValue)
        },
      })
    }

    items.push({
      label: "バックリンクへ移動",
      disabled: !this.hasBacklinksValue,
      action: () => this.scrollToBacklinks(),
    })

    return items
  }

  selectedText() {
    return (window.getSelection()?.toString() ?? "").trim()
  }

  /** @param {HTMLImageElement} img */
  async downloadImage(img) {
    const url = img.currentSrc || img.src
    if (!url) return

    const filename = this.filenameFromImageUrl(url)

    try {
      const response = await fetch(url, { credentials: "same-origin" })
      if (!response.ok) throw new Error("fetch failed")

      const blob = await response.blob()
      const blobUrl = URL.createObjectURL(blob)
      this.triggerDownload(blobUrl, filename)
      URL.revokeObjectURL(blobUrl)
    } catch {
      this.triggerDownload(url, filename)
    }
  }

  /** @param {string} url @param {string} filename */
  triggerDownload(url, filename) {
    const anchor = document.createElement("a")
    anchor.href = url
    anchor.download = filename
    anchor.rel = "noopener"
    anchor.style.display = "none"
    document.body.append(anchor)
    anchor.click()
    anchor.remove()
  }

  /** @param {string} url */
  filenameFromImageUrl(url) {
    try {
      const path = new URL(url, window.location.origin).pathname
      const segment = path.split("/").filter(Boolean).pop()
      return segment ? decodeURIComponent(segment) : "image"
    } catch {
      return "image"
    }
  }

  /** @param {string} text */
  async copySelection(text) {
    if (!text) return
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      this.copyWithExecCommand(text)
    }
  }

  /** @param {string} text */
  copyWithExecCommand(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "fixed"
    textarea.style.left = "-9999px"
    document.body.append(textarea)
    textarea.select()
    document.execCommand("copy")
    textarea.remove()
  }

  scrollToTop() {
    const scrollRoot =
      document.getElementById("memos_editor_scroll")
      ?? document.getElementById("notebook_memo_panel")

    if (scrollRoot) {
      scrollRoot.scrollTo({ top: 0, behavior: "smooth" })
      return
    }

    this.element.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  scrollToBacklinks() {
    const anchor = document.getElementById(this.backlinksAnchorValue)
    anchor?.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  /** @param {number} x @param {number} y @param {MenuItem[]} items */
  showMenu(x, y, items) {
    const menu = this.ensureMenuElement()
    menu.replaceChildren()

    for (const item of items) {
      if (item.separator) {
        const separator = document.createElement("div")
        separator.className = "memo-show-context-menu__separator"
        separator.setAttribute("role", "separator")
        menu.append(separator)
        continue
      }

      const button = document.createElement("button")
      button.type = "button"
      button.className = "memo-show-context-menu__item"
      button.disabled = Boolean(item.disabled)
      button.setAttribute("role", "menuitem")

      const label = document.createElement("span")
      label.className = "memo-show-context-menu__label"
      label.textContent = item.label ?? ""
      button.append(label)

      if (item.shortcut) {
        const shortcut = document.createElement("span")
        shortcut.className = "memo-show-context-menu__shortcut"
        shortcut.textContent = item.shortcut
        button.append(shortcut)
      }

      button.addEventListener("click", () => {
        this.hide()
        void item.action?.()
      })
      menu.append(button)
    }

    menu.hidden = false
    menu.style.left = "0px"
    menu.style.top = "0px"

    const margin = 8
    const rect = menu.getBoundingClientRect()
    let left = x
    let top = y

    if (left + rect.width > window.innerWidth - margin) {
      left = window.innerWidth - rect.width - margin
    }
    if (top + rect.height > window.innerHeight - margin) {
      top = window.innerHeight - rect.height - margin
    }

    menu.style.left = `${Math.max(margin, left)}px`
    menu.style.top = `${Math.max(margin, top)}px`
  }

  ensureMenuElement() {
    if (this.menuEl) return this.menuEl

    const menu = document.createElement("div")
    menu.className = "memo-show-context-menu"
    menu.hidden = true
    menu.setAttribute("role", "menu")
    document.body.append(menu)
    this.menuEl = menu
    return menu
  }

  hide() {
    if (this.menuEl) this.menuEl.hidden = true
    this.removeGlobalListeners()
  }

  addGlobalListeners() {
    document.addEventListener("click", this.boundHide)
    document.addEventListener("keydown", this.boundHideOnEscape)
    window.addEventListener("scroll", this.boundHide, true)
    window.addEventListener("resize", this.boundHide)
  }

  removeGlobalListeners() {
    document.removeEventListener("click", this.boundHide)
    document.removeEventListener("keydown", this.boundHideOnEscape)
    window.removeEventListener("scroll", this.boundHide, true)
    window.removeEventListener("resize", this.boundHide)
  }

  /** @param {KeyboardEvent} event */
  boundHideOnEscape = (event) => {
    if (event.key === "Escape") this.hide()
  }
}
