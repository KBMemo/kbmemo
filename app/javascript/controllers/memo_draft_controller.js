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
  static targets = ["body", "title", "titleManualFlag", "slug", "slugManualFlag", "tagList", "propertiesYaml", "directory"]
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

  tagListInput(event) {
    if (ifComposing(event)) return
    this._pending.tag_list = this.tagListTarget.value
    this.saveTagList()
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
    this.saveDraft({ memo_directory_id: this._pending.memo_directory_id })
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

  async patchDraft(changes) {
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    try {
      const res = await fetch(this.draftUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html, application/json"
        },
        body: JSON.stringify(this.memoPayload(changes))
      })
      if (!res.ok) return
      const ct = (res.headers.get("Content-Type") || "").toLowerCase()
      if (ct.includes("vnd.turbo-stream")) {
        const stream = await res.text()
        if (window.Turbo?.renderStreamMessage) {
          window.Turbo.renderStreamMessage(stream)
        }
      } else if (ct.includes("application/json")) {
        const data = await res.json()
        this.applyDraftServerPayload(data)
      }
    } catch (e) {
      console.error(e)
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
