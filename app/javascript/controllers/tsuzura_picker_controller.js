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
    this.detailTarget.replaceChildren()
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
        this.listTarget.replaceChildren(this._messageNode(message, "kb-text-danger"))
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
      this.listTarget.replaceChildren(this._messageNode("アルバムがありません", "kb-text-muted"))
      return
    }

    this.listTarget.replaceChildren(...albums.map((album) => this._albumButtonNode(album)))
  }

  _albumButtonNode(album) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "block w-full border-b kb-border px-3 py-2 text-left text-sm kb-hover-row"
    button.setAttribute("data-action", "tsuzura-picker#selectAlbum")
    button.dataset.albumId = String(album.id || "")

    const title = document.createElement("span")
    title.className = "font-medium kb-text-primary"
    title.textContent = String(album.title || "")
    button.append(title)

    const count = document.createElement("span")
    count.className = "kb-text-muted text-xs"
    count.textContent = ` · ${album.media_item_count ?? "?"} 枚`
    button.append(count)

    return button
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
      this.detailTarget.replaceChildren(this._messageNode("写真がありません", "kb-text-muted"))
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

    this.detailTarget.replaceChildren(...this._albumDetailNodes(album, ids, urlById))
  }

  _albumDetailNodes(album, ids, urlById) {
    const title = document.createElement("p")
    title.className = "px-3 py-2 text-sm font-medium kb-text-primary"
    title.textContent = String(album.title || "")

    const nodes = [title]
    if (!this.canSignThumbnails()) {
      nodes.push(this._messageNode("保存後のメモでサムネを表示できます。", "kb-text-muted", "py-1 text-xs"))
    }

    const list = document.createElement("ul")
    list.className = "max-h-56 overflow-y-auto"
    list.append(...ids.map((id) => this._mediaItemNode(id, urlById.get(id))))
    nodes.push(list)

    const overflow = ids.length > PICKER_THUMB_LIMIT ? ids.length - PICKER_THUMB_LIMIT : 0
    if (overflow > 0) {
      nodes.push(
        this._messageNode(
          `他 ${overflow} 件（サムネは先頭 ${PICKER_THUMB_LIMIT} 件）`,
          "kb-text-muted",
          "py-1 text-xs"
        )
      )
    }

    return nodes
  }

  _mediaItemNode(id, signedUrl) {
    const item = document.createElement("li")
    item.className = "border-b kb-border px-2 py-1.5"

    const label = document.createElement("label")
    label.className = "flex cursor-pointer items-center gap-2 text-sm"

    const input = document.createElement("input")
    input.type = "checkbox"
    input.value = id
    input.setAttribute("data-action", "change->tsuzura-picker#toggleMedia")
    label.append(input)

    label.append(this._thumbnailNode(signedUrl))

    const code = document.createElement("code")
    code.className = "min-w-0 truncate text-xs"
    code.textContent = id
    label.append(code)

    item.append(label)
    return item
  }

  _thumbnailNode(signedUrl) {
    if (signedUrl) {
      const image = document.createElement("img")
      image.src = signedUrl
      image.alt = ""
      image.className = "h-14 w-14 shrink-0 rounded object-cover border kb-border"
      image.loading = "lazy"
      image.decoding = "async"
      return image
    }

    const placeholder = document.createElement("span")
    placeholder.className =
      "kb-tsuzura-thumb-placeholder flex h-14 w-14 shrink-0 items-center justify-center rounded border kb-border kb-text-muted"
    placeholder.textContent = "—"
    return placeholder
  }

  _messageNode(message, toneClass, sizeClass = "py-2 text-sm") {
    const node = document.createElement("p")
    node.className = `px-3 ${sizeClass} ${toneClass}`
    node.textContent = message
    return node
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

}
