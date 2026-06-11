import { Controller } from "@hotwired/stimulus"

// メモ編集: 選択中の保存先ディレクトリをサイドバー文脈で開く
export default class extends Controller {
  static targets = ["button"]
  static values = {
    memoPath: String
  }

  connect() {
    this._directoryInput = this.element.querySelector(
      '[data-memo-directory-parent-picker-target="hiddenInput"]'
    )
    this._onDirectoryChange = () => this.updateButtonState()
    this._directoryInput?.addEventListener("change", this._onDirectoryChange)
    this.updateButtonState()
  }

  disconnect() {
    this._directoryInput?.removeEventListener("change", this._onDirectoryChange)
  }

  open(event) {
    event.preventDefault()
    event.stopPropagation()

    const directoryId = this._directoryInput?.value
    if (!directoryId || !this.memoPathValue) return

    const url = new URL(this.memoPathValue, window.location.origin)
    url.searchParams.set("memo_directory_id", directoryId)
    url.searchParams.delete("sidebar_view")
    url.searchParams.delete("tag_id")
    url.searchParams.delete("q")

    window.Turbo?.visit(url.toString()) ?? (window.location.href = url.toString())
  }

  updateButtonState() {
    if (!this.hasButtonTarget) return

    const enabled = Boolean(this._directoryInput?.value)
    this.buttonTarget.disabled = !enabled
    this.buttonTarget.classList.toggle("kb-inline-link", enabled)
    this.buttonTarget.classList.toggle("kb-text-secondary", !enabled)
  }
}
