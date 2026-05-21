import { Controller } from "@hotwired/stimulus"
import { loadAsciidocExtensions } from "../memo_body_editor/asciidoc_extensions"
import { wikiAutocompletion } from "../memo_body_editor/wiki_completion"
import { listContinuationExtension } from "../memo_body_editor/list_continuation"
import {
  readWysiwygPreference,
  wysiwygExtensionPack,
  writeWysiwygPreference
} from "../memo_body_editor/wysiwyg_pack"

const ACCEPTED_IMAGE_TYPE = /^image\/(png|jpeg|gif|webp|svg\+xml)$/i
const ACCEPTED_IMAGE_EXT = /\.(png|jpe?g|gif|webp|svg)$/i
const LIVE_PREVIEW_PREF_KEY = "kbmemo_memo_editor_live_preview"
const EDIT_MODE_PREF_KEY = "kbmemo_memo_editor_edit_mode"

function readLivePreviewPreference() {
  return localStorage.getItem(LIVE_PREVIEW_PREF_KEY) === "1"
}

function writeLivePreviewPreference(enabled) {
  localStorage.setItem(LIVE_PREVIEW_PREF_KEY, enabled ? "1" : "0")
}

function readEditModePreference() {
  return localStorage.getItem(EDIT_MODE_PREF_KEY) === "wysiwyg" ? "wysiwyg" : "source"
}

function writeEditModePreference(mode) {
  localStorage.setItem(EDIT_MODE_PREF_KEY, mode)
}

function imageFilesFrom(fileList) {
  return Array.from(fileList ?? []).filter(
    (file) => ACCEPTED_IMAGE_TYPE.test(file.type) || ACCEPTED_IMAGE_EXT.test(file.name)
  )
}

function imageFilesFromDataTransfer(dataTransfer) {
  if (!dataTransfer) return []

  const fromItems = []
  for (const item of dataTransfer.items ?? []) {
    if (item.kind !== "file") continue
    const file = item.getAsFile()
    if (!file) continue
    if (ACCEPTED_IMAGE_TYPE.test(file.type) || ACCEPTED_IMAGE_EXT.test(file.name)) {
      fromItems.push(file)
    }
  }
  if (fromItems.length > 0) return fromItems

  return imageFilesFrom(dataTransfer.files)
}

function dataTransferHasFiles(dataTransfer) {
  if (!dataTransfer) return false
  if (dataTransfer.files?.length > 0) return true
  const types = dataTransfer.types ? Array.from(dataTransfer.types) : []
  return types.includes("Files") || types.includes("application/x-moz-file")
}

const CLIPBOARD_IMAGE_EXT = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/gif": "gif",
  "image/webp": "webp",
  "image/svg+xml": "svg"
}

function extensionForImageType(type) {
  return CLIPBOARD_IMAGE_EXT[type?.toLowerCase()] || "png"
}

function withPasteFilename(file) {
  if (file.name && ACCEPTED_IMAGE_EXT.test(file.name)) return file
  const ext = extensionForImageType(file.type)
  return new File([file], `paste-${Date.now()}.${ext}`, { type: file.type })
}

function imageFilesFromClipboard(clipboardData) {
  if (!clipboardData) return []

  const fromItems = []
  for (const item of clipboardData.items ?? []) {
    if (item.kind !== "file" || !item.type.startsWith("image/")) continue
    const file = item.getAsFile()
    if (!file) continue
    if (!ACCEPTED_IMAGE_TYPE.test(file.type) && !ACCEPTED_IMAGE_EXT.test(file.name)) continue
    fromItems.push(withPasteFilename(file))
  }
  if (fromItems.length > 0) return fromItems

  return imageFilesFrom(clipboardData.files).map((file) => withPasteFilename(file))
}

/** 画像貼り付けとして扱うか（テキスト貼り付けは CodeMirror の既定動作に任せる） */
function shouldHandleImagePaste(clipboardData) {
  if (!clipboardData) return false

  const files = imageFilesFromClipboard(clipboardData)
  if (files.length === 0) return false

  const types = Array.from(clipboardData.types ?? [])

  // HTML 付きは通常のリッチテキスト貼り付けを優先（getData しない）
  if (types.includes("text/html")) return false

  if (types.includes("text/plain")) {
    const plain = clipboardData.getData("text/plain") ?? ""
    return plain.trim().length === 0
  }

  return true
}

// 本文 textarea（送信・memo-draft の参照用）と CodeMirror を同期する。
// CodeMirror は動的 import で初回のみ別チャンク読み込み。
export default class extends Controller {
  static targets = [
    "field",
    "host",
    "imageInput",
    "uploadError",
    "wysiwygToggle",
    "previewHost",
    "previewSkinSelect",
    "previewToggle",
    "sourcePane",
    "wysiwygPane",
    "wysiwygHost",
    "wysiwygToolbar",
    "editModeTab"
  ]
  static values = {
    labelId: String,
    wikiCompletionsUrl: String,
    wikiLinkLabelsUrl: String,
    memoId: String,
    uploadUrl: String
  }

  async connect() {
    if (!this.hasHostTarget || !this.hasFieldTarget) return

    const [{ EditorView, basicSetup }, { EditorState, Compartment }] = await Promise.all([
      import("codemirror"),
      import("@codemirror/state")
    ])

    const textarea = this.fieldTarget
    const getWikiConfig = () => ({
      url: this.wikiCompletionsUrlValue,
      memoId: this.memoIdValue || null
    })
    const getWikiLabelsConfig = () => ({
      url: this.wikiLinkLabelsUrlValue,
      memoId: this.memoIdValue || null
    })
    const getMemoId = () => this.memoIdValue || null

    const updateListener = EditorView.updateListener.of((vu) => {
      if (!vu.docChanged) return
      const next = vu.state.doc.toString()
      if (textarea.value !== next) {
        textarea.value = next
        textarea.dispatchEvent(new Event("input", { bubbles: true }))
      }
      this._livePreview?.scheduleRender()
    })

    const a11y = EditorView.contentAttributes.of({
      role: "textbox",
      "aria-multiline": "true",
      ...(this.hasLabelIdValue && this.labelIdValue
        ? { "aria-labelledby": this.labelIdValue }
        : { "aria-label": "メモ本文（AsciiDoc）" })
    })

    const theme = EditorView.theme({
      "&": {
        fontSize: "13px",
        minHeight: "18rem",
        fontFamily:
          'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace',
        borderRadius: "0",
        borderWidth: "0",
        outline: "none"
      },
      "&.cm-editor.cm-focused": { outline: "none" },
      ".cm-editor": {
        outline: "none",
        borderRadius: "0",
        backgroundColor: "transparent"
      },
      ".cm-line": { padding: "0", lineHeight: "1.625" },
      ".cm-content": {
        caretColor: "#18181b",
        paddingBlock: "0.5rem",
        paddingLeft: "0.375rem",
        paddingRight: "0",
        color: "#18181b",
        cursor: "text"
      },
      ".cm-cursor, .cm-dropCursor": {
        borderLeftWidth: "2px",
        borderLeftColor: "#18181b"
      },
      ".cm-selectionBackground": { background: "#bbf7d066" },
      ".cm-focused .cm-selectionBackground": { background: "#86efacb3" },
      ".cm-placeholder": { color: "#a1a1aa" },
      ".cm-activeLine": { background: "transparent" },
      ".cm-scroller": {
        overflow: "auto",
        fontFamily: "inherit",
        lineHeight: "inherit"
      },
      ".cm-gutters": {
        flexShrink: "0",
        borderRight: "1px solid #e4e4e7",
        backgroundColor: "#fafafa",
        color: "#71717a"
      },
      ".cm-gutters.cm-lineNumbers": {
        minWidth: "2.75rem",
        paddingRight: "0.5rem"
      },
      ".cm-lineNumbers .cm-gutterElement": {
        minWidth: "2ch",
        padding: "0 0.25rem 0 0",
        textAlign: "right"
      },
      ".cm-tooltip-autocomplete": {
        fontSize: "12px",
        borderRadius: "0.375rem",
        border: "1px solid #e4e4e7",
        boxShadow: "0 4px 6px -1px rgb(0 0 0 / 0.1)"
      },
      ".cm-completionLabel": { fontFamily: "inherit" },
      ".cm-completionDetail": { color: "#71717a", fontStyle: "normal" }
    })

    const startDoc = textarea.value
    const editorHost = this
    const wysiwygPackConfig = { getMemoId, getWikiLabelsConfig }
    this._wysiwygCompartment = new Compartment()
    this._wysiwygEnabled = readWysiwygPreference()
    const asciidocExts = await loadAsciidocExtensions()

    const state = EditorState.create({
      doc: startDoc,
      extensions: [
        basicSetup,
        EditorView.lineWrapping,
        ...asciidocExts,
        this._wysiwygCompartment.of(
          this._wysiwygEnabled ? wysiwygExtensionPack(wysiwygPackConfig) : []
        ),
        listContinuationExtension(),
        ...wikiAutocompletion(getWikiConfig),
        updateListener,
        a11y,
        theme,
        EditorView.domEventHandlers({
          blur: () => this.notifyBodyBlur(),
          dragover(event) {
            return editorHost.handleImageDragOver(event)
          },
          drop(event) {
            return editorHost.handleImageDrop(event)
          },
          paste(event) {
            return editorHost.handleImagePaste(event)
          }
        })
      ]
    })

    this.view = new EditorView({
      state,
      parent: this.hostTarget
    })

    textarea.addEventListener("change", this._onTextareaExternalChange)

    queueMicrotask(() => {
      this.view?.requestMeasure()
    })

    this._bindDragDrop()
    this._wysiwygPackConfig = wysiwygPackConfig
    this.syncWysiwygUi()
    this._bindInsertEvent()
    this._editMode = "source"
    this.syncEditModeUi()
    await this.setupLivePreview(textarea)
    if (this.hasWysiwygPaneTarget && readEditModePreference() === "wysiwyg") {
      await this.switchEditMode("wysiwyg")
    }
  }

  async setupLivePreview(textarea) {
    if (!this.hasPreviewHostTarget) return
    if (this._livePreview) return

    this._livePreviewEnabled = readLivePreviewPreference()
    this.syncLivePreviewUi()

    if (!this._livePreviewEnabled) return

    const { createLivePreview } = await import("../adoc_editor/mount.js")
    this._livePreview = createLivePreview({
      previewEl: this.previewHostTarget,
      skinSelectEl: this.hasPreviewSkinSelectTarget ? this.previewSkinSelectTarget : null,
      getMemoId: () => this.memoIdValue || null,
      getSource: () => this.view?.state.doc.toString() ?? textarea.value
    })
  }

  toggleLivePreview() {
    this._livePreviewEnabled = !this._livePreviewEnabled
    writeLivePreviewPreference(this._livePreviewEnabled)
    this.syncLivePreviewUi()

    if (this._livePreviewEnabled) {
      void this.setupLivePreview(this.fieldTarget)
      return
    }

    this._livePreview?.destroy()
    this._livePreview = null
  }

  syncLivePreviewUi() {
    if (this.hasPreviewToggleTarget) {
      this.previewToggleTarget.setAttribute("aria-pressed", this._livePreviewEnabled ? "true" : "false")
      this.previewToggleTarget.textContent = this._livePreviewEnabled ? "プレビュー非表示" : "ライブプレビュー"
    }
    this.element.classList.toggle("memo-body-editor--live-preview", !!this._livePreviewEnabled)
    if (this.hasPreviewHostTarget) {
      const previewPane = this.previewHostTarget.closest(".memo-body-editor__preview")
      if (previewPane) {
        previewPane.setAttribute("aria-hidden", this._livePreviewEnabled ? "false" : "true")
      }
    }
  }

  setEditMode(event) {
    const mode = event.currentTarget?.dataset?.editMode
    if (mode !== "source" && mode !== "wysiwyg") return
    void this.switchEditMode(mode)
  }

  async switchEditMode(mode) {
    if (this._editMode === mode) return

    if (this._editMode === "wysiwyg") {
      this._wysiwygEditor?.flush()
      this.updateCodeMirrorSource(this.fieldTarget.value)
    }

    this._editMode = mode
    writeEditModePreference(mode)

    if (mode === "wysiwyg") {
      const source = this.view?.state.doc.toString() ?? this.fieldTarget.value
      await this.ensureWysiwygEditor()
      this._wysiwygEditor.renderFromSource(source)
      this._wysiwygEditor.focus()
    }

    this.syncEditModeUi()
  }

  async ensureWysiwygEditor() {
    if (this._wysiwygEditor || !this.hasWysiwygHostTarget || !this.hasWysiwygToolbarTarget) return

    const { createMemoWysiwygEditor } = await import("../adoc_editor/wysiwyg_mount.js")
    this._wysiwygEditor = createMemoWysiwygEditor({
      editorEl: this.wysiwygHostTarget,
      toolbarEl: this.wysiwygToolbarTarget,
      paneEl: this.hasWysiwygPaneTarget ? this.wysiwygPaneTarget : null,
      getMemoId: () => this.memoIdValue || null,
      onSourceChange: (source) => this.syncSourceFromWysiwyg(source)
    })
  }

  syncSourceFromWysiwyg(source) {
    const textarea = this.fieldTarget
    if (textarea.value !== source) {
      textarea.value = source
      textarea.dispatchEvent(new Event("input", { bubbles: true }))
    }
    this.updateCodeMirrorSource(source)
    if (this._editMode === "source") {
      this._livePreview?.scheduleRender()
    }
  }

  updateCodeMirrorSource(source) {
    if (!this.view) return
    const cur = this.view.state.doc.toString()
    if (cur === source) return
    this.view.dispatch({
      changes: { from: 0, to: cur.length, insert: source }
    })
  }

  syncEditModeUi() {
    const isWysiwyg = this._editMode === "wysiwyg"
    this.element.classList.toggle("memo-body-editor--wysiwyg-mode", isWysiwyg)

    if (this.hasSourcePaneTarget) {
      this.sourcePaneTarget.hidden = isWysiwyg
      this.sourcePaneTarget.setAttribute("aria-hidden", isWysiwyg ? "true" : "false")
    }
    if (this.hasWysiwygPaneTarget) {
      this.wysiwygPaneTarget.hidden = !isWysiwyg
      this.wysiwygPaneTarget.setAttribute("aria-hidden", isWysiwyg ? "false" : "true")
    }

    for (const tab of this.editModeTabTargets) {
      const active = tab.dataset.editMode === this._editMode
      tab.classList.toggle("is-active", active)
      tab.setAttribute("aria-pressed", active ? "true" : "false")
    }
  }

  _bindInsertEvent() {
    this._handleInsert = (event) => {
      const text = event.detail?.text
      if (!text) return
      void this.insertAtCursor(text)
    }
    this.element.addEventListener("memo-body-editor:insert", this._handleInsert)
  }

  _unbindInsertEvent() {
    if (this._handleInsert) {
      this.element.removeEventListener("memo-body-editor:insert", this._handleInsert)
    }
  }

  toggleWysiwyg() {
    if (!this.view || !this._wysiwygCompartment) return
    this._wysiwygEnabled = !this._wysiwygEnabled
    writeWysiwygPreference(this._wysiwygEnabled)
    this.view.dispatch({
      effects: this._wysiwygCompartment.reconfigure(
        this._wysiwygEnabled ? wysiwygExtensionPack(this._wysiwygPackConfig) : []
      )
    })
    this.syncWysiwygUi()
    queueMicrotask(() => this.view?.requestMeasure())
  }

  syncWysiwygUi() {
    if (this.hasWysiwygToggleTarget) {
      this.wysiwygToggleTarget.textContent = this._wysiwygEnabled
        ? "ソース表示"
        : "プレビュー風"
      this.wysiwygToggleTarget.setAttribute(
        "aria-pressed",
        this._wysiwygEnabled ? "true" : "false"
      )
      this.wysiwygToggleTarget.title = this._wysiwygEnabled
        ? "マーカーを表示する（WYSIWYG オフ）"
        : "装飾プレビューを表示する（WYSIWYG オン）"
    }
    this.element.classList.toggle("memo-body-editor--source-only", !this._wysiwygEnabled)
  }

  canUploadImages() {
    return this.hasUploadUrlValue && this.uploadUrlValue
  }

  disconnect() {
    this._unbindInsertEvent()
    this._unbindDragDrop()
    this._wysiwygEditor?.flush()
    this._wysiwygEditor = null
    this._livePreview?.destroy()
    this._livePreview = null
    if (this.fieldTarget && this._onTextareaExternalChange) {
      this.fieldTarget.removeEventListener("change", this._onTextareaExternalChange)
    }
    if (this.view) {
      this.view.destroy()
      this.view = null
    }
    void import("../adoc_editor/mount.js").then(({ clearParseCache }) => clearParseCache())
  }

  _bindDragDrop() {
    if (this._dragDropBound) return
    this._dragDepth = 0
    const opts = { capture: true }
    this.element.addEventListener("dragenter", this._onDragEnter, opts)
    this.element.addEventListener("dragover", this._onElementDragOver, opts)
    this.element.addEventListener("dragleave", this._onDragLeave, opts)
    this.element.addEventListener("drop", this._onDrop, opts)
    this._dragDropBound = true
  }

  _unbindDragDrop() {
    if (!this._dragDropBound) return
    const opts = { capture: true }
    this.element.removeEventListener("dragenter", this._onDragEnter, opts)
    this.element.removeEventListener("dragover", this._onElementDragOver, opts)
    this.element.removeEventListener("dragleave", this._onDragLeave, opts)
    this.element.removeEventListener("drop", this._onDrop, opts)
    this._dragDropBound = false
    this._dragDepth = 0
    this.element.classList.remove("memo-body-editor--drag-over")
  }

  _onDragEnter = (event) => {
    if (!dataTransferHasFiles(event.dataTransfer)) return
    event.preventDefault()
    this._dragDepth += 1
    if (this.canUploadImages()) this.element.classList.add("memo-body-editor--drag-over")
  }

  _onElementDragOver = (event) => {
    this.handleImageDragOver(event)
  }

  _onDragLeave = (event) => {
    if (!dataTransferHasFiles(event.dataTransfer)) return
    this._dragDepth = Math.max(0, this._dragDepth - 1)
    if (this._dragDepth === 0) {
      this.element.classList.remove("memo-body-editor--drag-over")
    }
  }

  /** CodeMirror 上の dragover（テキストへのファイルパス挿入を抑止） */
  handleImageDragOver(event) {
    if (!dataTransferHasFiles(event.dataTransfer)) return false
    event.preventDefault()
    event.dataTransfer.dropEffect = this.canUploadImages() ? "copy" : "none"
    if (this.canUploadImages()) {
      this.element.classList.add("memo-body-editor--drag-over")
    }
    return true
  }

  /** エディタ／ツールバーへの drop */
  async handleImageDrop(event) {
    if (!dataTransferHasFiles(event.dataTransfer)) return false
    if (this._imageDropHandled) return true

    event.preventDefault()
    event.stopPropagation()
    this._imageDropHandled = true
    this._dragDepth = 0
    this.element.classList.remove("memo-body-editor--drag-over")

    try {
      if (!this.canUploadImages()) {
        this.showUploadError("メモを Git にコミットしてから画像を挿入できます")
        return true
      }

      const all = imageFilesFromDataTransfer(event.dataTransfer)
      const rejected =
        (event.dataTransfer.files?.length ?? 0) > 0 && all.length === 0

      if (all.length === 0) {
        if (rejected) {
          this.showUploadError("PNG / JPEG / GIF / WebP / SVG のみドロップできます")
        }
        return true
      }

      this.placeSelectionAtDrop(event)
      await this.uploadFiles(all)
      return true
    } finally {
      queueMicrotask(() => {
        this._imageDropHandled = false
      })
    }
  }

  _onDrop = (event) => {
    void this.handleImageDrop(event)
  }

  /**
   * クリップボード画像（スクリーンショット等）の貼り付け。
   * 同期で true/false を返す（async にすると Promise が truthy になり通常貼り付けが壊れる）。
   */
  handleImagePaste(event) {
    const clipboard = event.clipboardData
    if (!shouldHandleImagePaste(clipboard)) return false

    const files = imageFilesFromClipboard(clipboard)
    if (files.length === 0) return false

    event.preventDefault()
    event.stopPropagation()

    if (!this.canUploadImages()) {
      this.showUploadError("メモを Git にコミットしてから画像を貼り付けできます")
      return true
    }

    void this.uploadFiles(files).catch(() => {
      this.showUploadError("画像の貼り付けに失敗しました")
    })
    return true
  }

  placeSelectionAtDrop(event) {
    if (!this.view) return
    const pos = this.view.posAtCoords({ x: event.clientX, y: event.clientY })
    if (pos == null) return
    this.view.focus()
    this.view.dispatch({
      selection: { anchor: pos, head: pos },
      scrollIntoView: true
    })
  }

  notifyBodyBlur() {
    const ta = this.fieldTarget
    if (this.view) {
      const current = this.view.state.doc.toString()
      if (current !== ta.value) {
        ta.value = current
      }
    }
    ta.dispatchEvent(new FocusEvent("blur", { bubbles: true }))
  }

  async uploadImage(event) {
    const input = event?.currentTarget ?? (this.hasImageInputTarget ? this.imageInputTarget : null)
    if (!input) return

    const files = imageFilesFrom(input.files)
    if (files.length === 0) return

    await this.uploadFiles(files)
    input.value = ""
  }

  async uploadFiles(files) {
    if (!files?.length) return

    if (!this.hasUploadUrlValue || !this.uploadUrlValue) {
      this.showUploadError("画像のアップロード URL が未設定です。ページを再読み込みしてください。")
      return
    }

    this.clearUploadError()

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const inserted = []
    let failed = null

    for (const file of files) {
      const form = new FormData()
      form.append("file", file)

      try {
        const res = await fetch(this.uploadUrlValue, {
          method: "POST",
          body: form,
          headers: {
            Accept: "application/json",
            ...(token ? { "X-CSRF-Token": token } : {})
          },
          credentials: "same-origin"
        })

        let data = {}
        try {
          data = await res.json()
        } catch {
          data = {}
        }

        if (!res.ok) {
          failed = data.error || `${file.name}: アップロードに失敗しました`
          break
        }

        inserted.push(data.asciidoc || `image::${data.filename}[]`)
      } catch {
        failed = `${file.name}: アップロードに失敗しました`
        break
      }
    }

    if (inserted.length > 0) {
      await this.insertAtCursor(inserted.join("\n\n"))
    }

    if (failed) {
      const suffix =
        inserted.length > 0 ? `（${inserted.length} 件は挿入済み）` : ""
      this.showUploadError(`${failed}${suffix}`)
    }
  }

  getSelectedText() {
    if (!this.view) return ""
    const { from, to } = this.view.state.selection.main
    if (from === to) return ""
    return this.view.state.doc.sliceString(from, to)
  }

  async insertAtCursor(text) {
    if (this._editMode === "wysiwyg" && this._wysiwygEditor) {
      const textarea = this.fieldTarget
      const cur = textarea.value
      const sep = cur.length > 0 && !cur.endsWith("\n") ? "\n\n" : ""
      const next = cur + sep + text
      this.syncSourceFromWysiwyg(next)
      this._wysiwygEditor.renderFromSource(next)
      this._wysiwygEditor.focus()
      return
    }

    if (!this.view) {
      this.showUploadError("エディタの準備ができていません。少し待ってから再度お試しください。")
      return
    }

    const { state } = this.view
    const pos = state.selection.main.head
    this.view.dispatch({
      changes: { from: pos, to: pos, insert: text },
      selection: { anchor: pos + text.length, head: pos + text.length }
    })
    this.view.focus()

    const textarea = this.fieldTarget
    const next = this.view.state.doc.toString()
    if (textarea.value !== next) {
      textarea.value = next
      textarea.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  showUploadError(message) {
    if (!this.hasUploadErrorTarget) return
    this.uploadErrorTarget.textContent = message
    this.uploadErrorTarget.classList.remove("hidden")
  }

  clearUploadError() {
    if (!this.hasUploadErrorTarget) return
    this.uploadErrorTarget.textContent = ""
    this.uploadErrorTarget.classList.add("hidden")
  }

  /** Turbo などで値だけ差し替えた場合（将来用） */
  _onTextareaExternalChange = () => {
    if (!this.view) return
    const next = this.fieldTarget.value
    const cur = this.view.state.doc.toString()
    if (next === cur) return
    if (this._editMode === "wysiwyg" && this._wysiwygEditor) {
      this._wysiwygEditor.renderFromSource(next)
      return
    }
    this.view.dispatch({
      changes: { from: 0, to: cur.length, insert: next }
    })
    this._livePreview?.scheduleRender()
  }
}
