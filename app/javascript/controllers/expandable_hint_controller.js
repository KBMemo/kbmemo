import { Controller } from "@hotwired/stimulus"

// ラベル横の ▼/▲ で説明文パネルの表示を切り替える
export default class extends Controller {
  static targets = ["panel", "toggleButton", "toggleIcon"]
  static values = {
    expanded: { type: Boolean, default: false },
    expandLabel: String,
    collapseLabel: String
  }

  connect() {
    this.sync()
  }

  toggle() {
    this.expandedValue = !this.expandedValue
  }

  expandedValueChanged() {
    this.sync()
  }

  sync() {
    if (this.hasPanelTarget) {
      this.panelTarget.classList.toggle("hidden", !this.expandedValue)
    }
    if (this.hasToggleIconTarget) {
      this.toggleIconTarget.textContent = this.expandedValue ? "▲" : "▼"
    }
    const toggleBtn = this.hasToggleButtonTarget ? this.toggleButtonTarget : this.element.querySelector("[data-action*='toggle']")
    if (toggleBtn) {
      toggleBtn.setAttribute("aria-expanded", this.expandedValue ? "true" : "false")
      if (this.hasExpandLabelValue) {
        const label = this.expandedValue ? this.collapseLabelValue : this.expandLabelValue
        toggleBtn.title = label
        toggleBtn.setAttribute("aria-label", label)
      }
    }
  }
}
