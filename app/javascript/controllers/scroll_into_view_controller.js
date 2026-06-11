import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    block: { type: String, default: "start" },
    focus: { type: Boolean, default: true }
  }

  connect() {
    requestAnimationFrame(() => {
      this.element.scrollIntoView({ block: this.blockValue })
      if (this.focusValue && typeof this.element.focus === "function") {
        this.element.focus({ preventScroll: true })
      }
    })
  }
}
