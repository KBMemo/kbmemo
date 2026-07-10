import { Controller } from "@hotwired/stimulus"

// 思考・応答ログの <pre> をストリーム追従（Nyoy thinking-auto-scroll 相当）。
export default class extends Controller {
  static values = {
    intoView: { type: Boolean, default: false }
  }

  connect() {
    this.boundScroll = this.updateFollowState.bind(this)
    this.element.addEventListener("scroll", this.boundScroll, { passive: true })

    this.observer = new MutationObserver(() => this.followTail())
    this.observer.observe(this.element, {
      childList: true,
      characterData: true,
      subtree: true
    })

    this.following = true
    this.followTail()
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.boundScroll)
    this.observer?.disconnect()
  }

  updateFollowState() {
    this.following = this.atBottom()
  }

  followTail() {
    if (!this.following) return

    this.element.scrollTop = this.element.scrollHeight

    if (!this.intoViewValue) return

    requestAnimationFrame(() => {
      this.element.scrollIntoView({ block: "nearest", behavior: "instant" })
    })
  }

  atBottom() {
    const threshold = 24
    return (
      this.element.scrollHeight - this.element.scrollTop - this.element.clientHeight <=
      threshold
    )
  }
}
