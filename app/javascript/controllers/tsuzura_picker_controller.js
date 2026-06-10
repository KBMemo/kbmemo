import { Controller } from "@hotwired/stimulus"
import { fetchTsuzuraPreviewCache } from "@kbmemo/adoc-kbmemo"

const PICKER_THUMB_LIMIT = 48

export default class extends Controller {
  static targets = ["dialog", "list", "detail", "status", "insertAlbum", "insertImages"]
  static values = {
    albumsUrl: String,
    albumUrlTemplate: String,
    signUrlsUrl: String,
    memoId: Number,
    manageUrl: { type: String, default: "http://localhost:3008" },
    editorSelector: String
  }

  connect() {
    this._selectedMediaIds = new Set()
    this._currentAlbumId = null
    if (!this.hasDialogTarget) return

    this._onCancel = (event) => {
      event.preventDefault()
      this.close()
    }
    this.dialogTarget.addEventListener("cancel", this._onCancel)
  }

  disconnect() {
    if (!this.hasDialogTarget || !this._onCancel) return

    this.dialogTarget.removeEventListener("cancel", this._onCancel)
  }

  async open() {
    this._selectedMediaIds.clear()
    this._currentAlbumId = null
    this._setStatus("読み込み中…")
    this.detailTarget.innerHTML = ""
    this.insertAlbumTarget.disabled = true
    this.insertImagesTarget.disabled = true
    this.dialogTarget.showModal()
    await this._loadAlbums()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  async _loadAlbums() {
    try {
      const res = await fetch(this.albumsUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        const message =
          data.error ||
          `アルバム一覧を取得できませんでした（${res.status}）。Tsuzura（:3008）の起動と環境変数を確認してください。`
        this._setStatus(message)
        this.listTarget.innerHTML = `<p class="px-3 py-2 text-sm text-red-600">${this._escape(message)}</p>`
        return
      }
      this._renderAlbums(data.albums || [])
      const manageHint = this.manageUrlLabel()
      this._setStatus(
        (data.albums || []).length
          ? "アルバムを選んでください。"
          : `アルバムがありません。${manageHint} で作成できます。`
      )
    } catch (error) {
      console.error(error)
      this._setStatus("読み込みに失敗しました。")
    }
  }

  _renderAlbums(albums) {
    if (!albums.length) {
      this.listTarget.innerHTML = '<p class="px-3 py-2 text-sm kb-text-muted">アルバムがありません</p>'
      return
    }

    this.listTarget.innerHTML = albums
      .map((album) => {
        const count = album.media_item_count ?? "?"
        return `<button type="button" class="block w-full border-b kb-border px-3 py-2 text-left text-sm kb-hover-row" data-action="tsuzura-picker#selectAlbum" data-album-id="${this._escape(album.id)}">
          <span class="font-medium kb-text-primary">${this._escape(album.title)}</span>
          <span class="kb-text-muted text-xs"> · ${count} 枚</span>
        </button>`
      })
      .join("")
  }

  async selectAlbum(event) {
    const albumId = event.currentTarget.dataset.albumId
    if (!albumId) return

    this._currentAlbumId = albumId
    this._selectedMediaIds.clear()
    this._setStatus("写真を読み込み中…")
    this.insertAlbumTarget.disabled = false
    this.insertImagesTarget.disabled = true

    const url = this.albumUrlTemplateValue.replace("__ID__", encodeURIComponent(albumId))
    try {
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!res.ok) {
        this._setStatus("アルバムを開けませんでした。")
        return
      }
      const data = await res.json()
      await this._renderAlbumDetail(data)
      this._setStatus("挿入する項目を選んでください。")
    } catch (error) {
      console.error(error)
      this._setStatus("読み込みに失敗しました。")
    }
  }

  async _renderAlbumDetail(album) {
    const ids = (album.media_item_ids || []).map((id) => String(id).toUpperCase())
    if (!ids.length) {
      this.detailTarget.innerHTML = '<p class="px-3 py-2 text-sm kb-text-muted">写真がありません</p>'
      return
    }

    const thumbIds = ids.slice(0, PICKER_THUMB_LIMIT)
    let urlById = new Map()
    if (this.canSignThumbnails()) {
      const { urls } = await fetchTsuzuraPreviewCache(
        this.signUrlsUrlValue,
        String(this.memoIdValue),
        thumbIds,
        []
      )
      urlById = urls
    }

    const overflow = ids.length > PICKER_THUMB_LIMIT ? ids.length - PICKER_THUMB_LIMIT : 0
    const gridItems = ids
      .map((id) => {
        const signed = urlById.get(id)
        const thumb = signed
          ? `<img src="${this._escape(signed)}" alt="" class="h-14 w-14 shrink-0 rounded object-cover border kb-border" loading="lazy" decoding="async">`
          : `<span class="kb-tsuzura-thumb-placeholder flex h-14 w-14 shrink-0 items-center justify-center rounded border kb-border kb-text-muted">—</span>`
        return `<li class="border-b kb-border px-2 py-1.5">
            <label class="flex cursor-pointer items-center gap-2 text-sm">
              <input type="checkbox" value="${this._escape(id)}" data-action="change->tsuzura-picker#toggleMedia">
              ${thumb}
              <code class="min-w-0 truncate text-xs">${this._escape(id)}</code>
            </label>
          </li>`
      })
      .join("")

    const overflowNote =
      overflow > 0
        ? `<p class="px-3 py-1 text-xs kb-text-muted">他 ${overflow} 件（サムネは先頭 ${PICKER_THUMB_LIMIT} 件）</p>`
        : ""
    const thumbHint = this.canSignThumbnails()
      ? ""
      : '<p class="px-3 py-1 text-xs kb-text-muted">保存後のメモでサムネを表示できます。</p>'

    this.detailTarget.innerHTML = `
      <p class="px-3 py-2 text-sm font-medium kb-text-primary">${this._escape(album.title || "")}</p>
      ${thumbHint}
      <ul class="max-h-56 overflow-y-auto">
        ${gridItems}
      </ul>
      ${overflowNote}`
  }

  canSignThumbnails() {
    return Boolean(this.hasSignUrlsUrlValue && this.signUrlsUrlValue && this.hasMemoIdValue && this.memoIdValue)
  }

  toggleMedia(event) {
    const id = event.currentTarget.value?.toUpperCase()
    if (!id) return
    if (event.currentTarget.checked) {
      this._selectedMediaIds.add(id)
    } else {
      this._selectedMediaIds.delete(id)
    }
    this.insertImagesTarget.disabled = this._selectedMediaIds.size === 0
  }

  insertAlbum() {
    if (!this._currentAlbumId) return
    this._insertText(`album::${this._currentAlbumId}[]\n`)
    this._patchMemoProperty("media_album_id", this._currentAlbumId.toUpperCase())
  }

  insertImages() {
    if (this._selectedMediaIds.size === 0) return
    const lines = [...this._selectedMediaIds].sort().map((id) => `image::media:${id}[]`)
    this._insertText(`${lines.join("\n")}\n`)
  }

  _patchMemoProperty(key, value) {
    this.element.dispatchEvent(
      new CustomEvent("memo-draft:patch-property", {
        bubbles: true,
        detail: { key, value }
      })
    )
  }

  _insertText(text) {
    const editor = document.querySelector(this.editorSelectorValue)
    if (!editor) return

    editor.dispatchEvent(
      new CustomEvent("memo-body-editor:insert", {
        bubbles: true,
        detail: { text }
      })
    )
    this.close()
  }

  _setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  manageUrlLabel() {
    if (!this.hasManageUrlValue) return "Tsuzura（:3008）"
    try {
      const host = new URL(this.manageUrlValue, window.location.origin).host
      return host || this.manageUrlValue
    } catch {
      return this.manageUrlValue
    }
  }

  _escape(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
