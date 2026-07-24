import { Controller } from "@hotwired/stimulus"
import { useDebounce } from "stimulus-use"
import { csrfFetchHeaders, getCsrfToken } from "../lib/csrf_fetch.js"

const TITLE_PLACEHOLDER = " - 未入力 - "

function mergeTopLevelPropertiesYaml(yaml, key, value) {
  const lines = (yaml ?? "").split(/\r?\n/)
  const prefix = `${key}:`
  const kept = lines.filter((line) => !line.startsWith(prefix))
  if (value != null && value !== "") {
    const normalized = String(value).trim()
    const formatted = /^[0-9A-Z]{26}$/i.test(normalized)
      ? normalized.toUpperCase()
      : JSON.stringify(normalized)
    kept.push(`${key}: ${formatted}`)
  }
  return kept.join("\n").trim()
}

// ドラフトは常にフォームの現在値をまとめて PATCH/POST する（分割 PATCH の競合でサイドバーが古いままになるのを防ぐ）。
// 入力は debounce、ディレクトリ変更は即時送信。
export default class extends Controller {
  static debounces = ["autosaveDraft"]
  static targets = [
    "body",
    "title",
    "titleManualFlag",
    "tagList",
    "tagInput",
    "tagPills",
    "tagSuggestionsJson",
    "propertiesYaml",
    "discardDraftButton",
    "showMemoLink",
    "formActionsChrome",
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
    tagCatalog: { type: Array, default: [] },
    initialForm: { type: Object, default: {} }
  }

  connect() {
    useDebounce(this, { wait: this.debounceValue })
    this._creating = false
    this._formInteracted = false
    this._persistChain = Promise.resolve()
    this._tabId = crypto.randomUUID()
    this._pendingRemoteBody = null
    this._lastSavedBody = this.hasBodyTarget ? this.bodyTarget.value : null
    // 直近に保存済みのフォーム状態。これと一致する間は再 PATCH しない（無変更保存・本文未更新の抑止）。
    this._lastSavedSnapshot = JSON.stringify(this.buildMemoSnapshotOverrides())
    this._setupRemoteDraftChannel()
    this._onTurboRender = () => {
      if (this.isNewMemoForm() && !this._formInteracted) {
        this.scheduleNewMemoFormReset()
      }
    }
    document.addEventListener("turbo:render", this._onTurboRender)
    this._onPatchProperty = (event) => this.patchProperty(event)
    this.element.addEventListener("memo-draft:patch-property", this._onPatchProperty)
    if (this.isNewMemoForm()) {
      this.resetNewMemoFormFields()
    }
    queueMicrotask(() => {
      if (this.isNewMemoForm()) return
      this.syncTitleFromBodyIfBlank()
      this.hydrateTagSuggestionsCatalog()
      this.renderTagPillsFromHiddenIfPresent()
    })
  }

  disconnect() {
    document.removeEventListener("turbo:render", this._onTurboRender)
    if (this._onPatchProperty) {
      this.element.removeEventListener("memo-draft:patch-property", this._onPatchProperty)
    }
    this._remoteChannel?.close()
    this._remoteChannel = null
  }

  preventSubmit(event) {
    const form = this.memoFormElement()
    // button_to 削除など、シェル内の別 form の submit は対象外（バブリングで届く）
    if (!form || event.target !== form) return

    if (event.submitter?.dataset?.memoCommit === "true") {
      event.preventDefault()
      this.flushBodyEditor()
      void this.performCommit(event.target, event.submitter)
      return
    }
    event.preventDefault()
  }

  prepareShowNavigation(event) {
    if (event.button !== 0) return
    this.flushBodyEditor()
  }

  async performCommit(form, submitter) {
    if (!(form instanceof HTMLFormElement)) return

    const formData = new FormData(form)
    if (submitter?.name) {
      formData.append(submitter.name, submitter.value)
    }
    submitter?.setAttribute("disabled", "disabled")

    try {
      const res = await fetch(form.action, {
        method: form.method || "post",
        headers: { Accept: "text/vnd.turbo-stream.html" },
        body: formData,
        credentials: "same-origin"
      })
      const stream = await res.text()
      if (stream.trim() && window.Turbo?.renderStreamMessage) {
        window.Turbo.renderStreamMessage(stream)
      }
      if (res.ok) {
        const url = new URL(res.url, window.location.origin)
        if (url.href !== window.location.href) {
          window.history.pushState(window.history.state, "", url.href)
        }
      }
    } catch (e) {
      console.error(e)
      window.alert("コミットに失敗しました")
    } finally {
      submitter?.removeAttribute("disabled")
    }
  }

  flushBodyEditor() {
    this.element.dispatchEvent(
      new CustomEvent("kbmemo:flush-body-editor", { bubbles: true })
    )
  }

  markFormInteracted() {
    this._formInteracted = true
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
    this.markFormInteracted()
    if (ifComposing(event)) return
    const trimmed = this.titleTarget.value.trim()
    if (trimmed === "" || trimmed === TITLE_PLACEHOLDER) {
      // タイトルを空にしたら本文追従（manual=0）へ戻すが、ここで派生タイトルを
      // 即座に書き戻さない（全消しした瞬間に元へ戻る挙動を防ぐ）。空のまま編集を続けられる。
      if (this.hasTitleManualFlagTarget) {
        this.titleManualFlagTarget.value = "0"
      }
    } else if (this.hasTitleManualFlagTarget) {
      this.titleManualFlagTarget.value = "1"
    }
    this.autosaveDraft()
  }

  // タイトルを空のまま離れたら、本文追従の派生タイトルを表示へ反映する。
  // （編集中は空のまま、フォーカスを外したときだけ追従表示を復元する）
  titleBlur() {
    if (!this.hasTitleTarget || !this.hasBodyTarget) return
    const trimmed = this.titleTarget.value.trim()
    if (trimmed !== "" && trimmed !== TITLE_PLACEHOLDER) return

    if (this.hasTitleManualFlagTarget) {
      this.titleManualFlagTarget.value = "0"
    }
    const derived = this.derivedTitle(this.bodyTarget.value)
    // 未入力（本文1行目も空）は表示も空にして、サーバー描画（memo_title_input_value）と揃える。
    const display = derived === TITLE_PLACEHOLDER ? "" : derived
    if (this.titleTarget.value !== display) {
      this.titleTarget.value = display
      this.autosaveDraft()
    }
  }

  bodyInput(event) {
    this.markFormInteracted()
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
    const listId = input.dataset.tagSuggestionsList
    const dl = listId ? document.getElementById(listId) : null
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
    this.syncTagSuggestionsList()
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
      this.syncTagSuggestionsList()
      return
    }
    tags.push(raw)
    this.applyTags(tags)
    this.tagInputTarget.value = ""
    this.syncTagSuggestionsList()
  }

  syncTagSuggestionsList() {
    if (!this.hasTagInputTarget) return
    const input = this.tagInputTarget
    const listId = input.dataset.tagSuggestionsList
    if (input.value.trim() && listId) input.setAttribute("list", listId)
    else input.removeAttribute("list")
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

  applyMetadataSuggestion(event) {
    const title = event.detail?.title?.trim()
    const suggestedTags = Array.isArray(event.detail?.tags) ? event.detail.tags : []

    this.markFormInteracted()
    if (title && this.hasTitleTarget) {
      this.titleTarget.value = title
      if (this.hasTitleManualFlagTarget) this.titleManualFlagTarget.value = "1"
    }

    if (this.hasTagListTarget) {
      const tags = this.parseTagList(this.tagListTarget.value)
      const taken = new Set(tags.map((tag) => tag.toLowerCase()))
      for (const suggested of suggestedTags) {
        const tag = String(suggested).trim()
        if (!tag || taken.has(tag.toLowerCase())) continue
        tags.push(tag)
        taken.add(tag.toLowerCase())
      }
      this.applyTags(tags)
    } else {
      this.autosaveDraft()
    }
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
        "kb-tag-pill-link inline-flex max-w-full items-center gap-1 pl-3 pr-1 py-1",
        navigable ? "cursor-pointer" : ""
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
        ? "min-w-0 truncate underline kb-underline-border-strong"
        : "min-w-0 truncate"
      text.textContent = label
      pill.appendChild(text)

      const btn = document.createElement("button")
      btn.type = "button"
      btn.setAttribute("aria-label", "タグを削除")
      btn.setAttribute("data-action", "click->memo-draft#removeTagFromParam")
      btn.setAttribute("data-memo-draft-tag-index-param", String(index))
      btn.className =
        "ml-1 inline-flex h-5 w-5 shrink-0 items-center justify-center border-0 bg-transparent p-0 text-base leading-none kb-text-subtle hover:kb-text-secondary"
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

  patchProperty(event) {
    const { key, value } = event.detail ?? {}
    if (!key) return

    const field = this.propertiesField()
    if (!field) return

    field.value = mergeTopLevelPropertiesYaml(field.value, key, value)
    this.autosaveDraft()
  }

  derivedTitle(text) {
    const line = (text.split(/\r?\n/)[0] ?? "").trim()
    const stripped = line.replace(/^=+\s*/, "")
    return stripped || TITLE_PLACEHOLDER
  }

  shouldUseCreateEndpoint() {
    if (this.hasMemoIdValue && this.memoIdValue) return false
    if (this.hasDraftUrlValue && this.draftUrlValue) return false
    return Boolean(this.hasCreateUrlValue && this.createUrlValue)
  }

  isNewMemoForm() {
    return this.shouldUseCreateEndpoint()
  }

  initialFormSnapshot() {
    return this.hasInitialFormValue ? this.initialFormValue : {}
  }

  scheduleNewMemoFormReset() {
    this.resetNewMemoFormFields()
    queueMicrotask(() => this.resetNewMemoFormFields())
    requestAnimationFrame(() => this.resetNewMemoFormFields())
  }

  setFieldValue(field, value) {
    if (!field) return
    field.value = value ?? ""
  }

  propertiesField() {
    if (this.hasPropertiesYamlTarget) return this.propertiesYamlTarget
    return this.element.querySelector('textarea[name="memo[properties_yaml]"]')
  }

  visibilityField() {
    return this.element.querySelector('select[name="memo[visibility]"]')
  }

  memoGroupField() {
    return this.element.querySelector('select[name="memo[memo_group_id]"]')
  }

  resetNewMemoFormFields() {
    if (!this.isNewMemoForm() || this._formInteracted) return

    const initial = this.initialFormSnapshot()

    this.setFieldValue(this.hasTitleTarget ? this.titleTarget : null, initial.title ?? "")
    this.setFieldValue(
      this.hasTitleManualFlagTarget ? this.titleManualFlagTarget : null,
      initial.title_manual ?? "0"
    )
    const body = initial.body ?? ""
    if (this.hasBodyTarget) {
      this.bodyTarget.value = body
      this._lastSavedBody = body
    }
    this.element.dispatchEvent(
      new CustomEvent("kbmemo:reset-body-editor", { bubbles: true, detail: { body } })
    )

    this.setFieldValue(this.hasTagListTarget ? this.tagListTarget : null, initial.tag_list ?? "")
    this.setFieldValue(this.hasTagInputTarget ? this.tagInputTarget : null, "")
    this.setFieldValue(this.propertiesField(), initial.properties_yaml ?? "")

    const visibility = this.visibilityField()
    if (visibility && initial.visibility != null) {
      visibility.value = String(initial.visibility)
    }

    const memoGroup = this.memoGroupField()
    if (memoGroup) {
      memoGroup.value = initial.memo_group_id ?? ""
    }

    this.renderTagPillsFromHiddenIfPresent()
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
  }

  // 入力由来の自動保存（デバウンス）
  autosaveDraft() {
    void this.persistDraftMerged()
  }

  async directoryChange() {
    // 保存先はサーバー側で作成日から自動決定（クライアントから変更不可）
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

    const token = getCsrfToken()
    try {
      const res = await fetch(this.discardDraftUrlValue, {
        method: "PATCH",
        headers: {
          ...csrfFetchHeaders(),
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
    return { memo: merged }
  }

  buildMemoSnapshotOverrides(overrides = {}) {
    const memo = {}
    if (this.hasBodyTarget) memo.body = this.bodyTarget.value
    if (this.hasTitleTarget) memo.title = this.titleTarget.value
    memo.title_manual = !!(
      this.hasTitleManualFlagTarget && this.titleManualFlagTarget.value === "1"
    )
    if (this.hasPropertiesYamlTarget) {
      memo.properties_yaml = this.propertiesYamlTarget.value
    }
    if (this.hasTagListTarget) memo.tag_list = this.tagListTarget.value
    return { ...memo, ...overrides }
  }

  /**
   * 連続 PATCH を直列にしつつキュー送信（autosave と directory が混ざっても競合しない）
   */
  persistDraftMerged(overrides = {}, options = {}) {
    this._persistChain = this._persistChain.catch(() => {}).then(() =>
      this.performDraftAutosaveFetch(overrides, options)
    )
    return this._persistChain
  }

  async performDraftAutosaveFetch(overrides = {}, { stream = false } = {}) {
    this.flushBodyEditor()
    if (this._creating) return false
    const canPersist =
      (this.hasDraftUrlValue && this.draftUrlValue) ||
      this.shouldUseCreateEndpoint()
    if (!canPersist) return false

    const snapshot = this.buildMemoSnapshotOverrides(overrides)
    const snapshotKey = JSON.stringify(snapshot)

    // 既存メモのドラフト保存は、前回保存から実質変化がなければ送らない。
    // 本文未更新・blur・実質無変更のタイトル入力などでの無駄な PATCH／再描画を防ぐ。
    if (
      this.hasDraftUrlValue &&
      this.draftUrlValue &&
      snapshotKey === this._lastSavedSnapshot
    ) {
      return false
    }

    const wrapped = this.memoPayload(snapshot)
    const token = getCsrfToken()
    // 入力由来の自動保存は JSON で受け、本文タイピング中に title/slug/sidebar を
    // DOM ごと差し替える「ページ更新」を起こさない。turbo_stream はディレクトリ変更等の
    // 明示操作（stream: true）のときだけ使う。
    const wantsStream =
      stream &&
      typeof window !== "undefined" &&
      typeof window.Turbo?.renderStreamMessage === "function"
    const accept = wantsStream ? "text/vnd.turbo-stream.html" : "application/json"

    if (this.hasDraftUrlValue && this.draftUrlValue) {
      try {
        const res = await fetch(this.draftUrlValue, {
          method: "PATCH",
          headers: {
            ...csrfFetchHeaders(),
            "Content-Type": "application/json",
            Accept: accept
          },
          body: JSON.stringify(
            token ? { ...wrapped, authenticity_token: token } : wrapped
          )
        })
        if (!res.ok) return false
        const ct = (res.headers.get("Content-Type") || "").toLowerCase()
        if (ct.includes("vnd.turbo-stream")) {
          const streamHtml = await res.text()
          if (window.Turbo?.renderStreamMessage) {
            window.Turbo.renderStreamMessage(streamHtml)
          }
          this.notifyRemoteDraftSaved({ body: wrapped.memo?.body })
          this._lastSavedSnapshot = snapshotKey
          return true
        }
        if (ct.includes("application/json")) {
          const data = await res.json()
          this.applyDraftServerPayload(data)
          this.notifyRemoteDraftSaved({ body: wrapped.memo?.body, savedAt: data.saved_at })
          this._lastSavedSnapshot = snapshotKey
          return true
        }
        return false
      } catch (e) {
        console.error(e)
        return false
      }
    }

    if (this.shouldUseCreateEndpoint()) {
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
          ...csrfFetchHeaders(),
          "Content-Type": "application/json",
          Accept: "application/json"
        },
        body: JSON.stringify(
          token ? { ...wrapped, authenticity_token: token } : wrapped
        )
      })
      if (res.status === 201) {
        const data = await res.json()
        created = true
        this.promoteCreatedMemo(data)
        return true
      }
      if (res.status === 422) {
        const err = await res.json()
        const message =
          Array.isArray(err.errors) && err.errors.length > 0
            ? err.errors.join("\n")
            : "メモを作成できませんでした"
        console.error("メモを作成できませんでした:", err.errors ?? err)
        window.alert(message)
      }
    } catch (e) {
      console.error(e)
    } finally {
      if (!created) this._creating = false
    }
    return false
  }

  memoFormElement() {
    return this.element.matches("form")
      ? this.element
      : this.element.querySelector("form")
  }

  promoteCreatedMemo(data) {
    if (!data?.id) return

    if (data.draft_url) this.draftUrlValue = data.draft_url
    this.memoIdValue = data.id
    this.createUrlValue = ""
    this.element.removeAttribute("data-memo-draft-create-url-value")
    this._creating = false
    this._formInteracted = true

    const form = this.memoFormElement()
    if (!form) return
    if (data.update_url) {
      form.action = data.update_url
      let methodInput = form.querySelector('input[name="_method"]')
      if (!methodInput) {
        methodInput = document.createElement("input")
        methodInput.type = "hidden"
        methodInput.name = "_method"
        form.append(methodInput)
      }
      methodInput.value = "patch"
    }
    if (data.form_dom_id) {
      form.id = data.form_dom_id
      const commit = document.querySelector('[data-memo-commit="true"]')
      if (commit instanceof HTMLElement) {
        commit.setAttribute("form", data.form_dom_id)
      }
    }

    if (this.hasFormActionsChromeTarget) {
      this.formActionsChromeTarget.classList.remove("hidden")
      for (const el of this.formActionsChromeTarget.querySelectorAll("[data-promote-hidden]")) {
        el.classList.remove("hidden")
      }
      this.formActionsChromeTarget
        .querySelector('[data-memo-commit="true"]')
        ?.classList.remove("hidden")
    }
    if (this.hasShowMemoLinkTarget && data.show_path) {
      this.showMemoLinkTarget.href = data.show_path
    }

    if (data.edit_path) {
      const editUrl = new URL(data.edit_path, window.location.origin)
      editUrl.search = window.location.search
      window.history.replaceState(window.history.state, "", editUrl.toString())
    }

    this._lastSavedSnapshot = JSON.stringify(this.buildMemoSnapshotOverrides())
    this.element.dispatchEvent(
      new CustomEvent("kbmemo:memo-promoted", { bubbles: true, detail: data })
    )
  }

  applyDraftServerPayload(data) {
    if (typeof data.file_committed === "boolean") {
      this.fileCommittedValue = data.file_committed
    }
    this.syncDraftActionsUi(data)
  }

  syncDraftActionsUi(data) {
    if (typeof data.display_as_draft !== "boolean") return

    if (this.hasDiscardDraftButtonTarget) {
      this.discardDraftButtonTarget.classList.toggle("hidden", !data.display_as_draft)
    }
    if (this.hasShowMemoLinkTarget) {
      const showVisible = this.fileCommittedValue && !data.display_as_draft
      this.showMemoLinkTarget.classList.toggle("hidden", !showVisible)
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
