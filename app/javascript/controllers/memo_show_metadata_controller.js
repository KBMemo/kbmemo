import { Controller } from "@hotwired/stimulus"

function ifComposing(event) {
  return event.isComposing || event.keyCode === 229
}

export default class extends Controller {
  static targets = ["directoryInput", "tagList", "tagInput", "tagPills"]
  static values = {
    directoryUrl: String,
    tagsUrl: String,
    tagCatalog: Array,
    memoId: Number
  }

  connect() {
    this.lastSavedDirectoryId = this.hasDirectoryInputTarget ? this.directoryInputTarget.value : ""
    this.lastSavedDirectoryPath =
      this.element.querySelector('[data-memo-directory-parent-picker-target="pathLabel"]')?.textContent?.trim() ?? ""
    this.lastSavedTagList = this.hasTagListTarget ? this.tagListTarget.value : ""
    if (this.hasTagListTarget) {
      this.renderTagPills(this.parseTagList(this.tagListTarget.value))
    }
  }

  directoryChange() {
    if (!this.hasDirectoryInputTarget || !this.hasDirectoryUrlValue) return
    const id = this.directoryInputTarget.value
    if (!id || id === this.lastSavedDirectoryId) return
    void this.persistDirectory(id)
  }

  tagInputKeydown(event) {
    if (ifComposing(event)) return
    if (event.key === "Enter" || event.key === "," || event.key === "，") {
      event.preventDefault()
      this.commitTagInput()
      return
    }
    if (event.key === "Backspace" && this.tagInputTarget.value === "") {
      event.preventDefault()
      this.removeLastTag()
    }
  }

  tagInputChange() {
    this.commitTagInput()
  }

  tagInputInput(event) {
    if (ifComposing(event)) return
    if (event.inputType === "insertReplacementText") {
      queueMicrotask(() => this.commitTagInput())
    }
  }

  commitTagInput() {
    if (!this.hasTagInputTarget || !this.hasTagListTarget) return
    const raw = this.tagInputTarget.value.trim()
    if (!raw) return

    const tags = this.parseTagList(this.tagListTarget.value)
    if (tags.some((t) => t.toLowerCase() === raw.toLowerCase())) {
      this.tagInputTarget.value = ""
      return
    }
    tags.push(raw)
    this.tagInputTarget.value = ""
    void this.applyTags(tags)
  }

  removeTagFromParam(event) {
    event.stopPropagation()
    event.preventDefault()
    const index = Number.parseInt(event.params.tagIndex, 10)
    if (Number.isNaN(index)) return
    this.removeTagAt(index)
  }

  openTagInSidebarKeydown(event) {
    if (event.key !== "Enter" && event.key !== " ") return
    event.preventDefault()
    this.openTagInSidebar(event)
  }

  openTagInSidebar(event) {
    if (event.target.closest("button")) return
    const label = event.currentTarget.querySelector(":scope > span")?.textContent?.trim()
    if (!label || !this.hasMemoIdValue) return

    const tag = this.tagCatalogValue.find(
      (entry) => String(entry.name).toLowerCase() === label.toLowerCase()
    )
    if (!tag?.id) return

    const url = new URL(window.location.href)
    url.searchParams.set("sidebar_view", "tag")
    url.searchParams.set("tag_id", String(tag.id))
    url.searchParams.delete("memo_directory_id")
    url.searchParams.delete("q")
    window.location.assign(url.toString())
  }

  removeTagAt(index) {
    if (!this.hasTagListTarget) return
    const tags = this.parseTagList(this.tagListTarget.value)
    tags.splice(index, 1)
    void this.applyTags(tags)
  }

  removeLastTag() {
    if (!this.hasTagListTarget) return
    const tags = this.parseTagList(this.tagListTarget.value)
    if (tags.length === 0) return
    tags.pop()
    void this.applyTags(tags)
  }

  async applyTags(tags) {
    this.tagListTarget.value = tags.join(", ")
    this.renderTagPills(tags)
    await this.persistTags(tags.join(", "))
  }

  parseTagList(value) {
    return value
      .toString()
      .split(/[,，]/)
      .map((t) => t.trim())
      .filter(Boolean)
  }

  renderTagPills(tags) {
    if (!this.hasTagPillsTarget) return
    const root = this.tagPillsTarget
    root.replaceChildren()

    tags.forEach((label, index) => {
      const pill = document.createElement("span")
      const tagEntry = this.tagCatalogValue.find(
        (entry) => String(entry.name).toLowerCase() === label.toLowerCase()
      )
      const navigable = Boolean(tagEntry?.id && this.hasMemoIdValue)
      pill.className = [
        "inline-flex max-w-full items-center gap-1 rounded-full bg-white pl-3 pr-1 py-1 text-sm text-zinc-700 ring-1 ring-zinc-200",
        navigable ? "cursor-pointer hover:bg-zinc-50" : ""
      ]
        .filter(Boolean)
        .join(" ")
      if (navigable) {
        pill.setAttribute("role", "button")
        pill.setAttribute("tabindex", "0")
        pill.setAttribute("title", "サイドバーでこのタグを表示")
        pill.setAttribute(
          "data-action",
          "click->memo-show-metadata#openTagInSidebar keydown->memo-show-metadata#openTagInSidebarKeydown"
        )
      }

      const text = document.createElement("span")
      text.textContent = label
      pill.append(text)

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className =
        "inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-zinc-400 hover:bg-zinc-100 hover:text-zinc-700"
      remove.setAttribute("aria-label", `${label} を外す`)
      remove.setAttribute("data-action", "click->memo-show-metadata#removeTagFromParam")
      remove.setAttribute("data-memo-show-metadata-tag-index-param", String(index))
      remove.textContent = "×"
      pill.append(remove)

      root.append(pill)
    })
  }

  async persistDirectory(directoryId) {
    if (!this.hasDirectoryUrlValue || !this.directoryUrlValue) return
    const previous = this.lastSavedDirectoryId
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")

    try {
      const res = await fetch(this.directoryUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html, application/json"
        },
        body: JSON.stringify({ memo_directory_id: directoryId })
      })

      if (!res.ok) {
        this.revertDirectory(previous)
        return
      }

      this.lastSavedDirectoryId = directoryId
      await this.renderTurboStream(res)
    } catch {
      this.revertDirectory(previous)
    }
  }

  async persistTags(tagList) {
    if (!this.hasTagsUrlValue || !this.tagsUrlValue) return
    const previous = this.lastSavedTagList
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")

    try {
      const res = await fetch(this.tagsUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html, application/json"
        },
        body: JSON.stringify({ tag_list: tagList })
      })

      if (!res.ok) {
        this.revertTags(previous)
        return
      }

      this.lastSavedTagList = tagList
      await this.renderTurboStream(res)
    } catch {
      this.revertTags(previous)
    }
  }

  revertDirectory(previousId) {
    if (!this.hasDirectoryInputTarget) return
    this.directoryInputTarget.value = previousId
    const label = this.element.querySelector('[data-memo-directory-parent-picker-target="pathLabel"]')
    if (label) label.textContent = this.lastSavedDirectoryPath
  }

  revertTags(previousList) {
    if (!this.hasTagListTarget) return
    this.tagListTarget.value = previousList
    this.renderTagPills(this.parseTagList(previousList))
  }

  async renderTurboStream(res) {
    const ct = (res.headers.get("Content-Type") || "").toLowerCase()
    if (ct.includes("vnd.turbo-stream") && typeof window.Turbo?.renderStreamMessage === "function") {
      const stream = await res.text()
      if (stream.trim()) window.Turbo.renderStreamMessage(stream)
    }
  }
}
