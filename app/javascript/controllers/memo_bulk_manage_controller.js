import { Controller } from "@hotwired/stimulus"

// 管理画面のメモ一覧: チェックされたメモ ID を集計し、各一括操作フォーム送信時に memo_ids[] を注入する
export default class extends Controller {
  static targets = ["selectAll", "checkbox", "count", "form", "submitButton"]

  connect() {
    this.updateCount()
  }

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach((cb) => {
      if (!cb.disabled) cb.checked = checked
    })
    this.updateCount()
  }

  updateCount() {
    const boxes = this.checkboxTargets.filter((cb) => !cb.disabled)
    const selected = boxes.filter((cb) => cb.checked)
    const n = selected.length

    if (this.hasCountTarget) this.countTarget.textContent = String(n)

    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = n > 0 && n === boxes.length
      this.selectAllTarget.indeterminate = n > 0 && n < boxes.length
    }

    this.submitButtonTargets.forEach((btn) => {
      btn.disabled = n === 0
    })
  }

  injectSelection(event) {
    const form = event.currentTarget
    form.querySelectorAll("input[data-bulk-selection]").forEach((el) => el.remove())

    const ids = this.checkboxTargets
      .filter((cb) => !cb.disabled && cb.checked)
      .map((cb) => cb.value)

    if (ids.length === 0) {
      event.preventDefault()
      window.alert("メモを1件以上選択してください。")
      return
    }

    ids.forEach((id) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "memo_ids[]"
      input.value = id
      input.setAttribute("data-bulk-selection", "")
      form.appendChild(input)
    })
  }
}
