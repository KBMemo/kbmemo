import { Controller } from "@hotwired/stimulus"
import { useDebounce } from "stimulus-use"

const TITLE_PLACEHOLDER = " - 未入力 - "

// ドラフトは常にフォームの現在値をまとめて PATCH/POST する（分割 PATCH の競合でサイドバーが古いままになるのを防ぐ）。
// 入力は debounce、ディレクトリ変更は即時送信。
export default class extends Controller {
  static debounces = ["autosaveDraft"]
  static targets = [
    "body",
    "title",
    "titleManualFlag",
    "slug",
    "slugManualFlag",
    "tagList",
    "tagInput",
    "tagPills",
    "tagSuggestionsJson",
    "propertiesYaml",
    "directory",
    "remoteNotice",
    "remoteNoticeText"
  ]
  static values = {
    draftUrl: String,
    discardDraftUrl: String,
    createUrl: String,
    debounce: { type: Number, default: 800 },
    fileCommitted: { type: Boolean, default: false },
    memoId: Number,
    tagCatalog: { type: Array, default: [] }
  }

  connect() {
    useDebounce(this, { wait: this.debounceValue })
    this._creating = false
    this._persistChain = Promise.resolve()
    this._slugTouched = false
    this._tabId = crypto.randomUUID()
    this._pendingRemoteBody = null
    this._lastSavedBody = this.hasBodyTarget ? this.bodyTarget.value : null
    this._setupRemoteDraftChannel()
    queueMicrotask(() => {
      this.syncTitleFromBodyIfBlank()
      this.syncSlugFromTitleIfBlank()
      this.hydrateTagSuggestionsCatalog()
      this.renderTagPillsFromHiddenIfPresent()
    })
  }

  disconnect() {
    this._remoteChannel?.close()
    this._remoteChannel = null
  }

  preventSubmit(event) {
    if (event.submitter?.dataset?.memoCommit === "true") return
    event.preventDefault()
  }

  suppressEnterSubmit(event) {
    if (event.key !== "Enter" || event.defaultPrevented) return
    if (event.isComposing) return

    const el = event.target
    if (!(el instanceof HTMLElement)) return
    if (el.tagName === "TEXTAREA") return

    if (el.tagName === "BUTTON" && el.type === "submit") return
    if (el.tagName === "INPUT" && (el.type === "submit" || el.type === "image")) return

    if (el.tagName === "INPUT") {
      const t = el.type
      if (
        t === "submit" ||
        t === "button" ||
        t === "checkbox" ||
        t === "radio" ||
        t === "file" ||
        t === "hidden"
      ) {
        return
      }
      event.preventDefault()
    }
  }

  titleInput(event) {
    if (ifComposing(event)) return
    const trimmed = this.titleTarget.value.trim()
    if (trimmed === "" || trimmed === TITLE_PLACEHOLDER) {
      if (this.hasTitleManualFlagTarget) {
        this.titleManualFlagTarget.value = "0"
      }
      if (this.hasBodyTarget) {
        this.titleTarget.value = this.derivedTitle(this.bodyTarget.value)
      }
    } else if (this.hasTitleManualFlagTarget) {
      this.titleManualFlagTarget.value = "1"
    }
    this.autosaveDraft()
    this.maybeSyncSlugFromTitle()
  }

  bodyInput(event) {
    if (ifComposing(event)) return
    if (this.hasBodyTarget && this.hasTitleTarget) {
      const manual =
        this.hasTitleManualFlagTarget && this.titleManualFlagTarget.value === "1"
      const titleTrimmed = this.titleTarget.value.trim()
      const titleBlank = titleTrimmed === "" || titleTrimmed === TITLE_PLACEHOLDER
      if (!manual || titleBlank) {
        if (this.hasTitleManualFlagTarget && titleBlank) {
          this.titleManualFlagTarget.value = "0"
        }
        this.titleTarget.value = this.derivedTitle(this.bodyTarget.value)
      }
    }
    this.autosaveDraft()
    this.maybeSyncSlugFromTitle()
  }

  slugFocus() {
    if (this.fileCommittedValue) return
    this._slugTouched = true
  }

  slugInput(event) {
    if (ifComposing(event)) return
    if (this.fileCommittedValue) {
      this.autosaveDraft()
      return
    }
    const trimmed = this.slugTarget.value.trim()
    if (trimmed === "") {
      this._slugTouched = false
      if (this.hasSlugManualFlagTarget) {
        this.slugManualFlagTarget.value = "0"
      }
    } else {
      this._slugTouched = true
      if (this.hasSlugManualFlagTarget) {
        this.slugManualFlagTarget.value = "1"
      }
    }
    this.autosaveDraft()
  }

  renderTagPillsFromHiddenIfPresent() {
    if (!this.hasTagPillsTarget || !this.hasTagListTarget || !this.hasTagInputTarget) return
    this.renderTagPills(this.parseTagList(this.tagListTarget.value))
  }

  hydrateTagSuggestionsCatalog() {
    this._allTagSuggestionNames = []
    if (!this.hasTagSuggestionsJsonTarget) return
    const raw = this.tagSuggestionsJsonTarget.textContent?.trim()
    if (!raw) return
    try {
      const parsed = JSON.parse(raw)
      this._allTagSuggestionNames = Array.isArray(parsed) ? parsed.map(String) : []
    } catch {
      this._allTagSuggestionNames = []
    }
  }

  rebuildTagDatalistOptions() {
    if (!this.hasTagInputTarget || !this.hasTagListTarget) return
    const names = this._allTagSuggestionNames
    if (!Array.isArray(names) || names.length === 0) return

    const input = this.tagInputTarget
    const dl = input.list
    if (!dl) return

    const taken = new Set(this.parseTagList(this.tagListTarget.value).map((t) => t.toLowerCase()))
    dl.replaceChildren()
    for (const name of names) {
      if (taken.has(String(name).toLowerCase())) continue
      const opt = document.createElement("option")
      opt.value = name
      dl.appendChild(opt)
    }
  }

  tagInputKeydown(event) {
    if (!this.hasTagInputTarget) return
    if (event.target !== this.tagInputTarget) return
    if (event.isComposing) return

    if (event.key === "Enter") {
      event.preventDefault()
      event.stopPropagation()
      this.commitTagInput()
    } else if (event.key === "Backspace" && this.tagInputTarget.value === "") {
      event.stopPropagation()
      this.removeLastTag()
    }
  }

  tagInputChange() {
    if (!this.hasTagInputTarget || !this.hasTagListTarget) return
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
    this.applyTags(tags)
    this.tagInputTarget.value = ""
  }

  removeTagFromParam(event) {
    event.stopPropagation()
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
    url.pathname = `/memos/${this.memoIdValue}/edit`
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
    this.applyTags(tags)
  }

  removeLastTag() {
    if (!this.hasTagListTarget) return
    const tags = this.parseTagList(this.tagListTarget.value)
    if (tags.length === 0) return
    tags.pop()
    this.applyTags(tags)
  }

  parseTagList(value) {
    return value
      .toString()
      .split(/[,，]/)
      .map((t) => t.trim())
      .filter(Boolean)
  }

  stringifyTagList(tags) {
    return tags.join(", ")
  }

  applyTags(tags) {
    this.tagListTarget.value = this.stringifyTagList(tags)
    this.renderTagPills(tags)
    this.autosaveDraft()
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
        pill.setAttribute("data-action", "click->memo-draft#openTagInSidebar keydown->memo-draft#openTagInSidebarKeydown")
      }
      const text = document.createElement("span")
      text.className = navigable
        ? "min-w-0 truncate underline decoration-zinc-300"
        : "min-w-0 truncate"
      text.textContent = label
      pill.appendChild(text)

      const btn = document.createElement("button")
      btn.type = "button"
      btn.setAttribute("aria-label", "タグを削除")
      btn.setAttribute("data-action", "click->memo-draft#removeTagFromParam")
      btn.setAttribute("data-memo-draft-tag-index-param", String(index))
      btn.className =
        "shrink-0 rounded p-0.5 text-base leading-none text-zinc-400 hover:bg-zinc-100 hover:text-zinc-700"
      btn.textContent = "×"
      pill.appendChild(btn)

      root.appendChild(pill)
    })

    this.rebuildTagDatalistOptions()
  }

  propertiesInput(event) {
    if (ifComposing(event)) return
    this.autosaveDraft()
  }

  derivedTitle(text) {
    const line = (text.split(/\r?\n/)[0] ?? "").trim()
    const stripped = line.replace(/^=+\s*/, "")
    return stripped || TITLE_PLACEHOLDER
  }

  maybeSyncSlugFromTitle() {
    if (this.fileCommittedValue) return
    if (this._slugTouched) return
    if (!this.hasSlugTarget || !this.hasTitleTarget) return
    if (this.hasSlugManualFlagTarget && this.slugManualFlagTarget.value === "1") return
    if (this.hasSlugManualFlagTarget) {
      this.slugManualFlagTarget.value = "0"
    }
    this.autosaveDraft()
  }

  syncSlugFromTitleIfBlank() {
    if (this.fileCommittedValue) return
    if (this._slugTouched) return
    if (!this.hasSlugTarget || !this.hasTitleTarget) return
    if (this.hasSlugManualFlagTarget && this.slugManualFlagTarget.value === "1") return
    if (this.slugTarget.value.trim() !== "") return

    if (this.hasSlugManualFlagTarget) {
      this.slugManualFlagTarget.value = "0"
    }
    this.autosaveDraft()
  }

  syncTitleFromBodyIfBlank() {
    if (!this.hasTitleTarget || !this.hasBodyTarget) return
    if (!(this.hasDraftUrlValue && this.draftUrlValue)) return

    const titleTrimmed = this.titleTarget.value.trim()
    const titleBlank =
      titleTrimmed === "" || titleTrimmed === TITLE_PLACEHOLDER
    if (!titleBlank) return

    const derived = this.derivedTitle(this.bodyTarget.value)
    if (this.titleTarget.value === derived) return

    this.titleTarget.value = derived
    if (this.hasTitleManualFlagTarget) {
      this.titleManualFlagTarget.value = "0"
    }
    this.autosaveDraft()
    void this.maybeSyncSlugFromTitle()
  }

  // 入力由来の自動保存（デバウンス）
  autosaveDraft() {
    void this.persistDraftMerged()
  }

  async directoryChange() {
    if (!this.hasDirectoryTarget) return
    const id = this.directoryTarget.value
    await this.persistDraftMerged({ memo_directory_id: id })
  }

  discardDraft(event) {
    event?.preventDefault()
    void this.performDiscardDraft()
  }

  async performDiscardDraft() {
    if (!this.hasDiscardDraftUrlValue || !this.discardDraftUrlValue) return
    if (
      !window.confirm(
        "ドラフトの変更を破棄し、最後にコミットした内容を読み込みます。よろしいですか？"
      )
    ) {
      return
    }

    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    try {
      const res = await fetch(this.discardDraftUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": token,
          Accept: "application/json"
        }
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({}))
        const message =
          Array.isArray(err.errors) && err.errors.length > 0
            ? err.errors.join("\n")
            : "復元に失敗しました"
        window.alert(message)
        return
      }
      const data = await res.json()
      const navigate = window.Turbo?.visit ?? ((url) => window.location.assign(url))
      navigate(data.edit_path || window.location.href)
    } catch (e) {
      console.error(e)
      window.alert("復元に失敗しました")
    }
  }

  normalizeOutgoingTitle(value) {
    return value?.trim() ? value : TITLE_PLACEHOLDER
  }

  memoPayload(memoAttrs) {
    const merged = { ...memoAttrs }
    if (Object.prototype.hasOwnProperty.call(merged, "title")) {
      merged.title = this.normalizeOutgoingTitle(merged.title)
    }
    if (Object.prototype.hasOwnProperty.call(merged, "slug_manual")) {
      merged.slug_manual = !!merged.slug_manual
    }
    return { memo: merged }
  }

  buildMemoSnapshotOverrides(overrides = {}) {
    const memo = {}
    if (this.hasBodyTarget) memo.body = this.bodyTarget.value
    if (this.hasTitleTarget) memo.title = this.titleTarget.value
    memo.title_manual = !!(
      this.hasTitleManualFlagTarget && this.titleManualFlagTarget.value === "1"
    )
    if (this.hasSlugTarget) memo.slug = this.slugTarget.value
    memo.slug_manual = !!(
      this.hasSlugManualFlagTarget && this.slugManualFlagTarget.value === "1"
    )
    if (this.hasPropertiesYamlTarget) {
      memo.properties_yaml = this.propertiesYamlTarget.value
    }
    if (this.hasTagListTarget) memo.tag_list = this.tagListTarget.value
    if (this.hasDirectoryTarget) memo.memo_directory_id = this.directoryTarget.value
    return { ...memo, ...overrides }
  }

  /**
   * 連続 PATCH を直列にしつつキュー送信（autosave と directory が混ざっても競合しない）
   */
  persistDraftMerged(overrides = {}) {
    this._persistChain = this._persistChain.catch(() => {}).then(() =>
      this.performDraftAutosaveFetch(overrides)
    )
    return this._persistChain
  }

  async performDraftAutosaveFetch(overrides = {}) {
    if (this._creating) return false
    const canPersist =
      (this.hasDraftUrlValue && this.draftUrlValue) ||
      (this.hasCreateUrlValue && this.createUrlValue)
    if (!canPersist) return false

    const snapshot = this.buildMemoSnapshotOverrides(overrides)
    const wrapped = this.memoPayload(snapshot)
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    const accept =
      typeof window !== "undefined" &&
      typeof window.Turbo?.renderStreamMessage === "function"
        ? "text/vnd.turbo-stream.html"
        : "application/json"

    if (this.hasDraftUrlValue && this.draftUrlValue) {
      try {
        const res = await fetch(this.draftUrlValue, {
          method: "PATCH",
          headers: {
            "X-CSRF-Token": token,
            "Content-Type": "application/json",
            Accept: accept
          },
          body: JSON.stringify(wrapped)
        })
        if (!res.ok) return false
        const ct = (res.headers.get("Content-Type") || "").toLowerCase()
        if (ct.includes("vnd.turbo-stream")) {
          const stream = await res.text()
          if (window.Turbo?.renderStreamMessage) {
            window.Turbo.renderStreamMessage(stream)
          }
          this.notifyRemoteDraftSaved({ body: wrapped.memo?.body })
          return true
        }
        if (ct.includes("application/json")) {
          const data = await res.json()
          this.applyDraftServerPayload(data)
          this.notifyRemoteDraftSaved({ body: wrapped.memo?.body, savedAt: data.saved_at })
          return true
        }
        return false
      } catch (e) {
        console.error(e)
        return false
      }
    }

    if (this.hasCreateUrlValue && this.createUrlValue) {
      return this.performCreateMemoFetch(wrapped, token)
    }

    return false
  }

  async performCreateMemoFetch(wrapped, token) {
    this._creating = true
    let created = false
    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "application/json"
        },
        body: JSON.stringify(wrapped)
      })
      if (res.status === 201) {
        const data = await res.json()
        created = true
        const navigate = window.Turbo?.visit ?? ((url) => window.location.assign(url))
        navigate(data.edit_path)
        return true
      }
      if (res.status === 422) {
        const err = await res.json()
        console.error("メモを作成できませんでした:", err.errors)
      }
    } catch (e) {
      console.error(e)
    } finally {
      if (!created) this._creating = false
    }
    return false
  }

  applyDraftServerPayload(data) {
    if (Object.prototype.hasOwnProperty.call(data, "slug") && this.hasSlugTarget) {
      this.slugTarget.value = data.slug ?? ""
    }
    if (typeof data.slug_manual === "boolean" && this.hasSlugManualFlagTarget) {
      this.slugManualFlagTarget.value = data.slug_manual ? "1" : "0"
    }
    if (typeof data.file_committed === "boolean") {
      this.fileCommittedValue = data.file_committed
    }
  }

  applyRemoteDraft() {
    if (this._pendingRemoteBody == null || !this.hasBodyTarget) return
    this.applyRemoteBody(this._pendingRemoteBody)
    this._pendingRemoteBody = null
    this.hideRemoteNotice()
  }

  _setupRemoteDraftChannel() {
    if (!this.hasMemoIdValue || typeof BroadcastChannel === "undefined") return
    this._remoteChannel = new BroadcastChannel(`kbmemo.memo.${this.memoIdValue}`)
    this._remoteChannel.onmessage = (event) => this._onRemoteDraftMessage(event.data)
  }

  _onRemoteDraftMessage(data) {
    if (!data || data.tabId === this._tabId) return
    if (typeof data.body !== "string" || !this.hasBodyTarget) return

    const dirty = this.bodyTarget.value !== this._lastSavedBody
    if (dirty) {
      this._pendingRemoteBody = data.body
      this.showRemoteNotice()
      return
    }

    this.applyRemoteBody(data.body)
  }

  notifyRemoteDraftSaved({ body, savedAt }) {
    if (typeof body === "string") {
      this._lastSavedBody = body
    } else if (this.hasBodyTarget) {
      this._lastSavedBody = this.bodyTarget.value
    }

    if (!this._remoteChannel) return
    this._remoteChannel.postMessage({
      tabId: this._tabId,
      body: this._lastSavedBody,
      savedAt: savedAt ?? new Date().toISOString()
    })
  }

  applyRemoteBody(body) {
    if (!this.hasBodyTarget) return
    this.bodyTarget.value = body
    this._lastSavedBody = body
    this.bodyTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.bodyTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  showRemoteNotice() {
    if (!this.hasRemoteNoticeTarget) return
    this.remoteNoticeTarget.classList.remove("hidden")
  }

  hideRemoteNotice() {
    if (!this.hasRemoteNoticeTarget) return
    this.remoteNoticeTarget.classList.add("hidden")
  }
}

function ifComposing(event) {
  return event?.isComposing || event?.inputType === "insertCompositionText"
}
