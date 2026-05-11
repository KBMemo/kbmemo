import { Controller } from "@hotwired/stimulus"
import { useDebounce } from "stimulus-use"

const TITLE_PLACEHOLDER = " - 未入力 - "

// フィールド単位でデバウンス保存。新規は初回 POST → 編集へ遷移。
export default class extends Controller {
  static debounces = ["saveBody", "saveTitle", "saveTitleManual", "saveSlug", "saveTagList", "saveProperties"]
  static targets = ["body", "title", "titleManualFlag", "slug", "tagList", "propertiesJson"]
  static values = {
    draftUrl: String,
    createUrl: String,
    debounce: { type: Number, default: 800 }
  }

  connect() {
    useDebounce(this, { wait: this.debounceValue })
    this._creating = false
    this._pending = {}
  }

  preventSubmit(event) {
    event.preventDefault()
  }

  titleInput(event) {
    if (ifComposing(event)) return
    if (this.hasTitleManualFlagTarget) {
      this.titleManualFlagTarget.value = "1"
    }
    this._pending.title = this.titleTarget.value
    this._pending.title_manual = true
    this.saveTitle()
    this.saveTitleManual()
  }

  bodyInput(event) {
    if (ifComposing(event)) return
    if (this.hasBodyTarget && this.hasTitleTarget) {
      const manual = this.hasTitleManualFlagTarget && this.titleManualFlagTarget.value === "1"
      if (!manual) {
        this.titleTarget.value = this.derivedTitle(this.bodyTarget.value)
        this._pending.title = this.titleTarget.value
        this._pending.title_manual = false
        this.saveTitle()
        this.saveTitleManual()
      }
    }
    this._pending.body = this.bodyTarget.value
    this.saveBody()
  }

  slugInput(event) {
    if (ifComposing(event)) return
    this._pending.slug = this.slugTarget.value
    this.saveSlug()
  }

  tagListInput(event) {
    if (ifComposing(event)) return
    this._pending.tag_list = this.tagListTarget.value
    this.saveTagList()
  }

  propertiesInput(event) {
    if (ifComposing(event)) return
    this._pending.properties_json = this.propertiesJsonTarget.value
    this.saveProperties()
  }

  derivedTitle(text) {
    const line = (text.split(/\r?\n/)[0] ?? "").trim()
    const stripped = line.replace(/^=+\s*/, "")
    return stripped || TITLE_PLACEHOLDER
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

  saveTagList() {
    this.saveDraft({ tag_list: this._pending.tag_list })
  }

  saveProperties() {
    this.saveDraft({ properties_json: this._pending.properties_json })
  }

  normalizeOutgoingTitle(value) {
    return value?.trim() ? value : TITLE_PLACEHOLDER
  }

  memoPayload(changes) {
    const merged = { ...changes }
    if (Object.prototype.hasOwnProperty.call(merged, "title")) {
      merged.title = this.normalizeOutgoingTitle(merged.title)
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
      if (res.ok) {
        const stream = await res.text()
        if (window.Turbo?.renderStreamMessage) {
          window.Turbo.renderStreamMessage(stream)
        }
      }
    } catch (e) {
      console.error(e)
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
