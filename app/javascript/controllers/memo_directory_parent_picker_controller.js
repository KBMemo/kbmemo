import { Controller } from "@hotwired/stimulus"

// ディレクトリ編集: 親ディレクトリのツリーピッカー（▼ で開閉）
export default class extends Controller {
  static targets = ["panel", "toggleButton", "hiddenInput", "pathLabel", "option"]

  connect() {
    this.refreshOptionTabindexes()
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

  toggleKeydown(event) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return

    event.preventDefault()
    event.stopPropagation()
    this.show()
    const options = this.visibleOptionTargets()
    const selected = this.selectedOption() || options[0]
    const target = event.key === "ArrowUp" ? (selected || options.at(-1)) : (selected || options[0])
    this.focusOption(target)
  }

  panelKeydown(event) {
    const options = this.visibleOptionTargets()
    if (!options.length) return

    const current = event.target instanceof HTMLElement
      ? event.target.closest('[data-memo-directory-parent-picker-target~="option"]')
      : null
    const currentIndex = current ? options.indexOf(current) : -1

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.focusOption(options[this.nextOptionIndex(currentIndex, options.length)])
        break
      case "ArrowUp":
        event.preventDefault()
        this.focusOption(options[this.previousOptionIndex(currentIndex, options.length)])
        break
      case "Home":
        event.preventDefault()
        this.focusOption(options[0])
        break
      case "End":
        event.preventDefault()
        this.focusOption(options[options.length - 1])
        break
      case "Escape":
        event.preventDefault()
        this.hide({ focusToggle: true })
        break
      case "Enter":
      case " ":
        if (current instanceof HTMLButtonElement) {
          event.preventDefault()
          current.click()
        }
        break
    }
  }

  toggleBranch(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const branch = button.closest("[data-directory-picker-branch]")
    const children = branch?.querySelector(":scope > .kb-directory-picker-children")
    if (!branch || !children) return

    const expanded = button.getAttribute("aria-expanded") === "true"
    const nextExpanded = !expanded
    button.setAttribute("aria-expanded", String(nextExpanded))
    branch.dataset.directoryPickerOpen = String(nextExpanded)
    children.hidden = !nextExpanded
    this.refreshOptionTabindexes()
  }

  select(event) {
    event.preventDefault()
    event.stopPropagation()
    const button = event.currentTarget
    const directoryId = button.dataset.directoryId
    const directoryPath = button.dataset.directoryPath
    const directoryFullPath = button.dataset.directoryFullPath ?? ""
    if (directoryId == null || directoryPath == null) return

    this.hiddenInputTarget.value = directoryId
    this.pathLabelTarget.textContent = directoryPath
    this.markSelected(button)
    this.hiddenInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.dispatch("directory-selected", {
      detail: { fullPath: directoryFullPath, labeledPath: directoryPath, directoryId }
    })
    this.hide()
  }

  markSelected(button) {
    const selectedClass = ["kb-selected-row", "font-medium", "kb-text-primary"]
    const unselectedClass = ["kb-text-secondary"]

    this.optionTargets.forEach((el) => {
      el.classList.remove(...selectedClass)
      el.classList.add(...unselectedClass)
      el.setAttribute("aria-selected", "false")
      el.tabIndex = -1
    })

    button.classList.remove(...unselectedClass)
    button.classList.add(...selectedClass)
    button.setAttribute("aria-selected", "true")
    button.tabIndex = 0
  }

  isOpen() {
    return !this.panelTarget.classList.contains("hidden")
  }

  show() {
    const wasOpen = this.isOpen()
    this.panelTarget.classList.remove("hidden")
    this.toggleButtonTarget.setAttribute("aria-expanded", "true")
    this.refreshOptionTabindexes()
    if (wasOpen) return

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

  hide({ focusToggle = false } = {}) {
    this.panelTarget.classList.add("hidden")
    this.toggleButtonTarget.setAttribute("aria-expanded", "false")
    this.restoreInitialDetailsState()
    this.teardownDocumentListeners()
    if (focusToggle) this.toggleButtonTarget.focus()
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

  refreshOptionTabindexes() {
    const selected = this.selectedOption()
    const fallback = this.visibleOptionTargets()[0]
    const active = selected || fallback

    this.optionTargets.forEach((option) => {
      option.tabIndex = option === active ? 0 : -1
    })
  }

  selectedOption() {
    return this.optionTargets.find((option) => option.getAttribute("aria-selected") === "true")
  }

  visibleOptionTargets() {
    return this.optionTargets.filter((option) => !option.closest("[hidden]"))
  }

  focusOption(option) {
    if (!option) return

    this.optionTargets.forEach((candidate) => {
      candidate.tabIndex = candidate === option ? 0 : -1
    })
    option.focus()
  }

  nextOptionIndex(currentIndex, length) {
    return currentIndex >= 0 ? (currentIndex + 1) % length : 0
  }

  previousOptionIndex(currentIndex, length) {
    return currentIndex >= 0 ? (currentIndex - 1 + length) % length : length - 1
  }

  restoreInitialDetailsState() {
    this.panelTarget
      .querySelectorAll("[data-directory-picker-branch]")
      .forEach((branch) => {
        const open = branch.dataset.directoryPickerInitialOpen === "true"
        const button = branch.querySelector(":scope > .kb-directory-picker-caret")
        const children = branch.querySelector(":scope > .kb-directory-picker-children")
        branch.dataset.directoryPickerOpen = String(open)
        button?.setAttribute("aria-expanded", String(open))
        if (children) children.hidden = !open
      })
  }
}
