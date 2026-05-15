import { Controller } from "@hotwired/stimulus"
import { useDebounce } from "stimulus-use"

const TITLE_PLACEHOLDER = " - 未入力 - "

// フィールド単位でデバウンス保存。新規は初回 POST → 編集へ遷移。
export default class extends Controller {
  static debounces = [
    "saveBody",
    "saveTitle",
    "saveTitleManual",
    "saveSlug",
    "saveSlugManual",
    "saveSlugSyncedFromTitle",
    "saveTagList",
    "saveProperties",
    "saveDirectory"
  ]
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
    "directory"
  ]
  static values = {
    draftUrl: String,
    createUrl: String,
    debounce: { type: Number, default: 800 },
    fileCommitted: { type: Boolean, default: false }
  }

  connect() {
    useDebounce(this, { wait: this.debounceValue })
    this._creating = false
    this._pending = {}
    this._slugTouched = false
    queueMicrotask(() => {
      this.syncTitleFromBodyIfBlank()
      this.syncSlugFromTitleIfBlank()
      this.hydrateTagSuggestionsCatalog()
      this.renderTagPillsFromHiddenIfPresent()
    })
  }

  preventSubmit(event) {
    // コミットボタン（明示クリック／そのボタンにフォーカスして Enter）以外はフル送信しない
    if (event.submitter?.dataset?.memoCommit === "true") return
    event.preventDefault()
  }

  // 単一行入力で Enter したときの暗黙のフォーム送信を抑止（コミット以外で画面遷移しない）
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
      this._pending.title = this.titleTarget.value
      this._pending.title_manual = false
    } else {
      if (this.hasTitleManualFlagTarget) {
        this.titleManualFlagTarget.value = "1"
      }
      this._pending.title = this.titleTarget.value
      this._pending.title_manual = true
    }
    this.saveTitle()
    this.saveTitleManual()
    this.maybeSyncSlugFromTitle()
  }

  bodyInput(event) {
    if (ifComposing(event)) return
    if (this.hasBodyTarget && this.hasTitleTarget) {
      const manual = this.hasTitleManualFlagTarget && this.titleManualFlagTarget.value === "1"
      const titleTrimmed = this.titleTarget.value.trim()
      const titleBlank =
        titleTrimmed === "" || titleTrimmed === TITLE_PLACEHOLDER
      if (!manual || titleBlank) {
        if (this.hasTitleManualFlagTarget && titleBlank) {
          this.titleManualFlagTarget.value = "0"
        }
        this.titleTarget.value = this.derivedTitle(this.bodyTarget.value)
        this._pending.title = this.titleTarget.value
        this._pending.title_manual = false
        this.saveTitle()
        this.saveTitleManual()
      }
    }
    this._pending.body = this.bodyTarget.value
    this.saveBody()
    this.maybeSyncSlugFromTitle()
  }

  slugFocus() {
    if (this.fileCommittedValue) return
    this._slugTouched = true
  }

  slugInput(event) {
    if (ifComposing(event)) return
    if (this.fileCommittedValue) {
      this._pending.slug = this.slugTarget.value
      this.saveSlug()
      return
    }
    const trimmed = this.slugTarget.value.trim()
    if (trimmed === "") {
      this._slugTouched = false
      if (this.hasSlugManualFlagTarget) {
        this.slugManualFlagTarget.value = "0"
      }
      this._pending.slug_manual = false
      // クライアントで memo-{id} を出さず、サーバー決定 + Turbo で欄を更新
      this.saveSlugSyncedFromTitle()
    } else {
      this._slugTouched = true
      if (this.hasSlugManualFlagTarget) {
        this.slugManualFlagTarget.value = "1"
      }
      this._pending.slug = this.slugTarget.value
      this._pending.slug_manual = true
      this.saveSlug()
      this.saveSlugManual()
    }
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
    const index = Number.parseInt(event.params.tagIndex, 10)
    if (Number.isNaN(index)) return
    this.removeTagAt(index)
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
    this._pending.tag_list = this.tagListTarget.value
    this.saveTagList()
  }

  renderTagPills(tags) {
    if (!this.hasTagPillsTarget) return
    const root = this.tagPillsTarget
    root.replaceChildren()

    tags.forEach((label, index) => {
      const pill = document.createElement("span")
      pill.className =
        "inline-flex max-w-full items-center gap-1 rounded-full bg-white pl-3 pr-1 py-1 text-sm text-zinc-700 ring-1 ring-zinc-200"
      const text = document.createElement("span")
      text.className = "min-w-0 truncate"
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
    this._pending.properties_yaml = this.propertiesYamlTarget.value
    this.saveProperties()
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
    this._pending.slug_manual = false
    // スラッグはサーバー（MeCab 等）で決め、Turbo で欄を更新。タイトルも同梱してずれを防ぐ。
    this.saveSlugSyncedFromTitle()
  }

  saveSlugSyncedFromTitle() {
    this.saveDraft({
      slug_manual: false,
      title: this.normalizeOutgoingTitle(this.titleTarget.value),
      title_manual: !!(this.hasTitleManualFlagTarget && this.titleManualFlagTarget.value === "1")
    })
  }

  // スラッグ欄が空のときタイトルから埋める（初回ファイル保存前のみ）
  syncSlugFromTitleIfBlank() {
    if (this.fileCommittedValue) return
    if (this._slugTouched) return
    if (!this.hasSlugTarget || !this.hasTitleTarget) return
    if (this.hasSlugManualFlagTarget && this.slugManualFlagTarget.value === "1") return
    if (this.slugTarget.value.trim() !== "") return

    if (this.hasSlugManualFlagTarget) {
      this.slugManualFlagTarget.value = "0"
    }
    this._pending.slug_manual = false
    this.saveSlugSyncedFromTitle()
  }

  // タイトル欄が空のときは本文1行目と同期（編集画面初回表示・ドラフト後の追従用）
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
    this._pending.title = derived
    this._pending.title_manual = false
    this.saveTitle()
    this.saveTitleManual()
    this.maybeSyncSlugFromTitle()
  }

  saveBody() {
    this.saveDraft({ body: this._pending.body })
  }

  saveTitle() {
    this.saveDraft({ title: this._pending.title })
  }

  saveTitleManual() {
    this.saveDraft({ title_manual: this._pending.title_manual })
  }

  saveSlug() {
    this.saveDraft({ slug: this._pending.slug })
  }

  saveSlugManual() {
    this.saveDraft({ slug_manual: this._pending.slug_manual })
  }

  saveTagList() {
    this.saveDraft({ tag_list: this._pending.tag_list })
  }

  saveProperties() {
    this.saveDraft({ properties_yaml: this._pending.properties_yaml })
  }

  directoryChange() {
    if (!this.hasDirectoryTarget) return
    this._pending.memo_directory_id = this.directoryTarget.value
    this.saveDirectory()
  }

  saveDirectory() {
    const id = this._pending.memo_directory_id
    this.patchDraft({ memo_directory_id: id }, { turboOnly: true }).then((ok) => {
      if (ok && id) this.syncSidebarDirectoryQueryParam(id)
    })
  }

  syncSidebarDirectoryQueryParam(directoryId) {
    const url = new URL(window.location.href)
    url.searchParams.set("memo_directory_id", directoryId)
    url.searchParams.delete("sidebar_view")
    url.searchParams.delete("tag_id")
    history.replaceState({}, "", url)
  }

  normalizeOutgoingTitle(value) {
    return value?.trim() ? value : TITLE_PLACEHOLDER
  }

  memoPayload(changes) {
    const merged = { ...changes }
    if (Object.prototype.hasOwnProperty.call(merged, "title")) {
      merged.title = this.normalizeOutgoingTitle(merged.title)
    }
    if (Object.prototype.hasOwnProperty.call(merged, "slug_manual")) {
      merged.slug_manual = !!merged.slug_manual
    }
    return {
      memo: merged
    }
  }

  async saveDraft(changes) {
    if (this._creating) return
    const canSave =
      (this.hasDraftUrlValue && this.draftUrlValue) ||
      (this.hasCreateUrlValue && this.createUrlValue)
    if (!canSave) return

    if (this.hasDraftUrlValue && this.draftUrlValue) {
      await this.patchDraft(changes)
    } else if (this.hasCreateUrlValue && this.createUrlValue) {
      await this.createMemo(changes)
    }
  }

  async patchDraft(changes, options = {}) {
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    const accept = options.turboOnly
      ? "text/vnd.turbo-stream.html"
      : "text/vnd.turbo-stream.html, application/json"
    try {
      const res = await fetch(this.draftUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: accept
        },
        body: JSON.stringify(this.memoPayload(changes))
      })
      if (!res.ok) return false
      const ct = (res.headers.get("Content-Type") || "").toLowerCase()
      if (ct.includes("vnd.turbo-stream")) {
        const stream = await res.text()
        if (window.Turbo?.renderStreamMessage) {
          window.Turbo.renderStreamMessage(stream)
        }
        return true
      }
      if (ct.includes("application/json")) {
        const data = await res.json()
        this.applyDraftServerPayload(data)
        return true
      }
      return false
    } catch (e) {
      console.error(e)
      return false
    }
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

  async createMemo(changes) {
    if (this._creating) return
    this._creating = true
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    let created = false
    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "application/json"
        },
        body: JSON.stringify(this.memoPayload(changes))
      })
      if (res.status === 201) {
        const data = await res.json()
        created = true
        const navigate = window.Turbo?.visit ?? ((url) => { window.location.assign(url) })
        navigate(data.edit_path)
        return
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
  }

}

function ifComposing(event) {
  return event?.isComposing || event?.inputType === "insertCompositionText"
}
