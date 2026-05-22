import { Controller } from "@hotwired/stimulus"
import { applyOpenDirectoryIds, loadOpenDirectoryIds, syncOpenDirectoryIdsFromPanel } from "../memo_directory_nav_open.js"

export default class extends Controller {
  connect() {
    applyOpenDirectoryIds(loadOpenDirectoryIds(), this.element)
    this._onToggle = () => syncOpenDirectoryIdsFromPanel()
    this.element.addEventListener("toggle", this._onToggle, true)
  }

  disconnect() {
    this.element.removeEventListener("toggle", this._onToggle, true)
  }
}
