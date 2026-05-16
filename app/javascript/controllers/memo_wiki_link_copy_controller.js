import { Controller } from "@hotwired/stimulus"

// メモ編集: [[slug-{memo_id}]] 形式の Wiki リンク文字列をクリップボードへコピー
export default class extends Controller {
  static targets = ["button"]
  static values = {
    slugInput: { type: String, default: "#memo_slug" }
  }

  connect() {
    this._slugInputEl = document.querySelector(this.slugInputValue)
    this._onSlugInput = () => this.updateButtonState()
    this._slugInputEl?.addEventListener("input", this._onSlugInput)
    this.updateButtonState()
  }

  disconnect() {
    this._slugInputEl?.removeEventListener("input", this._onSlugInput)
  }

  copy(event) {
    event.preventDefault()
    event.stopPropagation()

    const reference = this.buildReference()
    if (!reference) {
      this.showNotice("コピーできません。スラッグを確認してください。")
      return
    }

    this.copyText(reference)
      .then(() => {
        this.showNotice(`Wiki リンクをコピーしました: ${reference}`)
      })
      .catch(() => {
        this.showNotice("クリップボードへのコピーに失敗しました。")
      })
  }

  async copyText(text) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
      return
    }

    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "fixed"
    textarea.style.left = "-9999px"
    document.body.appendChild(textarea)
    textarea.select()
    const ok = document.execCommand("copy")
    textarea.remove()
    if (!ok) throw new Error("copy failed")
  }

  buildReference() {
    const slug = this.slugInput()?.value?.trim()
    if (!slug) return null

    return `[[${slug}]]`
  }

  slugInput() {
    return this._slugInputEl ?? document.querySelector(this.slugInputValue)
  }

  updateButtonState() {
    if (!this.hasButtonTarget) return

    const enabled = Boolean(this.slugInput()?.value?.trim())
    this.buttonTarget.disabled = !enabled
    this.buttonTarget.classList.toggle("opacity-40", !enabled)
    this.buttonTarget.classList.toggle("cursor-not-allowed", !enabled)
  }

  showNotice(message) {
    document.dispatchEvent(
      new CustomEvent("flash-notice:show", {
        detail: { message },
        bubbles: true
      })
    )
  }
}
