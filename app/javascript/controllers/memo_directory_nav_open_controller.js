import { Controller } from "@hotwired/stimulus"
import { applyOpenDirectoryIds, loadOpenDirectoryIds, setBranchOpen, syncOpenDirectoryIdsFromPanel } from "../memo_directory_nav_open.js"

export default class extends Controller {
  connect() {
    applyOpenDirectoryIds(loadOpenDirectoryIds(), this.element)
    this.revealSelectedDirectory()
    this._scrollFrame = window.requestAnimationFrame(() => {
      this._scrollFrame = window.requestAnimationFrame(() => this.scrollSelectedDirectory())
    })
  }

  disconnect() {
    if (this._scrollFrame) window.cancelAnimationFrame(this._scrollFrame)
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

  revealSelectedDirectory() {
    const selected = this.selectedDirectoryLink()
    if (!selected) return

    for (const branch of selected.closest(".kb-memo-directory-tree-scroll")
      ?.querySelectorAll("[data-memo-directory-nav-branch]") || []) {
      if (branch.contains(selected)) setBranchOpen(branch, true)
    }
  }

  scrollSelectedDirectory() {
    const selected = this.selectedDirectoryLink()
    if (!selected) return

    selected.scrollIntoView({ block: "center", inline: "nearest", behavior: "auto" })
    const scroller = selected.closest(".kb-memo-directory-tree-scroll")
    if (scroller) scroller.dataset.selectedDirectoryScrolled = "true"
  }

  selectedDirectoryLink() {
    return this.element.querySelector(".kb-memo-directory-tree-scroll .kb-sidebar-nav.is-active")
  }
}
