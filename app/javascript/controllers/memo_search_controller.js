import { Controller } from "@hotwired/stimulus"
import { useDebounce } from "stimulus-use"

// サイドバー: タイトル・本文検索（入力デバウンスで GET 送信）
export default class extends Controller {
  static debounces = ["submitSearch"]
  static targets = ["input", "form"]
  static values = { debounce: { type: Number, default: 400 } }

  connect() {
    useDebounce(this, { wait: this.debounceValue })
  }

  submitSearch() {
    if (!this.hasFormTarget) return
    this.formTarget.requestSubmit()
  }

  clear(event) {
    event.preventDefault()
    if (!this.hasInputTarget) return
    this.inputTarget.value = ""
    window.location.assign("/memos?sidebar_view=search")
  }
}
