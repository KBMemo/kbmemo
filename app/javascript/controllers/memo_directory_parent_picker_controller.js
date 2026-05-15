import { Controller } from "@hotwired/stimulus"

// ディレクトリ編集: 親ディレクトリのツリーピッカー（▼ で開閉）
export default class extends Controller {
  static targets = ["panel", "toggleButton", "hiddenInput", "pathLabel", "option"]

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

  select(event) {
    event.preventDefault()
    event.stopPropagation()
    const button = event.currentTarget
    const directoryId = button.dataset.directoryId
    const directoryPath = button.dataset.directoryPath
    if (directoryId == null || directoryPath == null) return

    this.hiddenInputTarget.value = directoryId
    this.pathLabelTarget.textContent = directoryPath
    this.markSelected(button)
    this.hiddenInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.hide()
  }

  markSelected(button) {
    const selectedClass = ["bg-zinc-200", "font-medium", "text-zinc-900"]
    const unselectedClass = ["text-zinc-700"]

    this.optionTargets.forEach((el) => {
      el.classList.remove(...selectedClass)
      el.classList.add(...unselectedClass)
      el.setAttribute("aria-selected", "false")
    })

    button.classList.remove(...unselectedClass)
    button.classList.add(...selectedClass)
    button.setAttribute("aria-selected", "true")
  }

  isOpen() {
    return !this.panelTarget.classList.contains("hidden")
  }

  show() {
    this.panelTarget.classList.remove("hidden")
    this.toggleButtonTarget.setAttribute("aria-expanded", "true")
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
    this.toggleButtonTarget.setAttribute("aria-expanded", "false")
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
