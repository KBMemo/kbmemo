import { Controller } from "@hotwired/stimulus"
import { applyOpenDirectoryIds, loadOpenDirectoryIds, setBranchOpen, syncOpenDirectoryIdsFromPanel } from "../memo_directory_nav_open.js"

export default class extends Controller {
  connect() {
    applyOpenDirectoryIds(loadOpenDirectoryIds(), this.element)
  }

  toggle(event) {
    event.preventDefault()

    const button = event.currentTarget
    const branch = button.closest("[data-memo-directory-nav-branch]")
    if (!branch) return

    const open = branch.dataset.memoDirectoryNavOpen === "true"
    setBranchOpen(branch, !open)
    syncOpenDirectoryIdsFromPanel()
  }
}
