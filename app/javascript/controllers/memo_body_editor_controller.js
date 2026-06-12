import { Controller } from "@hotwired/stimulus"
import {
  MEMO_SOURCE_SNIPPETS,
  applySnippetToEditorView,
  filterMemoSourceSnippets,
} from "../adoc_editor/snippet_support"

const ACCEPTED_IMAGE_TYPE = /^image\/(png|jpeg|gif|webp|svg\+xml)$/i
const ACCEPTED_IMAGE_EXT = /\.(png|jpe?g|gif|webp|svg)$/i
const LIVE_PREVIEW_PREF_KEY = "kbmemo_memo_editor_live_preview"
const EDIT_MODE_PREF_KEY = "kbmemo_memo_editor_edit_mode"
let editorChromePromise = null
let kbmemoEditorPromise = null

function loadEditorChrome() {
  editorChromePromise ??= Promise.all([
    import("@kbmemo/adoc-wysiwyg/contextMenu.css"),
    import("@kbmemo/adoc-wysiwyg"),
  ]).then(([, mod]) => mod)
  return editorChromePromise
}

function loadKbmemoEditorExtensions() {
  kbmemoEditorPromise ??= Promise.all([
    import("../adoc_editor/kbmemo_asciidoc_extensions"),
    import("../../../packages/adoc-kbmemo/kbmemo_host.js"),
    import("../../../packages/adoc-kbmemo/src/list_continuation.js"),
    import("../../../packages/adoc-kbmemo/src/wiki_completion.js"),
  ]).then(([adocExtensions, host, listContinuation, wikiCompletion]) => ({
    loadAsciidocExtensions: adocExtensions.loadAsciidocExtensions,
    configureKbmemoHost: host.configureKbmemoHost,
    listContinuationExtension: listContinuation.listContinuationExtension,
    resetHostConfig: host.resetHostConfig,
    wikiAutocompletion: wikiCompletion.wikiAutocompletion,
  }))
  return kbmemoEditorPromise
}

function getCsrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

function readLivePreviewPreference() {
  return localStorage.getItem(LIVE_PREVIEW_PREF_KEY) === "1"
}

function writeLivePreviewPreference(enabled) {
  localStorage.setItem(LIVE_PREVIEW_PREF_KEY, enabled ? "1" : "0")
}

function readEditModePreference() {
  const stored = localStorage.getItem(EDIT_MODE_PREF_KEY)
  if (stored === "source") return "source"
  return "wysiwyg"
}

function writeEditModePreference(mode) {
  localStorage.setItem(EDIT_MODE_PREF_KEY, mode)
}

function removeLegacyGlobalAsciidoctorStylesheet() {
  document.getElementById("kbmemo-adoc-preview-base")?.remove()
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

function suggestedPasteFilename(file) {
  const ext = extensionForImageType(file.type)
  return `paste-${Date.now()}.${ext}`
}

function fileWithFilename(file, filename) {
  const trimmed = filename.trim()
  const name = ACCEPTED_IMAGE_EXT.test(trimmed)
    ? trimmed
    : `${trimmed}.${extensionForImageType(file.type)}`
  return new File([file], name, { type: file.type })
}

function imageFilesFromClipboard(clipboardData) {
  if (!clipboardData) return []

  const fromItems = []
  for (const item of clipboardData.items ?? []) {
    if (item.kind !== "file") continue
    const file = item.getAsFile()
    if (!file) continue
    const type = (file.type || item.type || "").toLowerCase()
    if (ACCEPTED_IMAGE_TYPE.test(type) || ACCEPTED_IMAGE_EXT.test(file.name)) {
      fromItems.push(file)
      continue
    }
    // スクリーンショット等で MIME が空のことがある
    if (!type || type === "application/octet-stream") {
      fromItems.push(file)
    }
  }
  if (fromItems.length > 0) return fromItems

  return imageFilesFrom(clipboardData.files)
}

function clipboardPlainText(clipboardData) {
  const types = Array.from(clipboardData.types ?? [])
  if (!types.includes("text/plain")) return ""
  return clipboardData.getData("text/plain") ?? ""
}

function clipboardHtml(clipboardData) {
  const types = Array.from(clipboardData.types ?? [])
  if (!types.includes("text/html")) return ""
  return clipboardData.getData("text/html") ?? ""
}

function looksLikeLocalFilePath(text) {
  const value = text.trim()
  if (!value) return false
  return /^([a-z]+:|\\\\|\/|\.\/|\.\.\/).+\.(png|jpe?g|gif|webp|svg)$/i.test(value)
}

/** HTML が画像ラッパーだけなら画像ペーストとして扱う（スクリーンショット等） */
function isImageOnlyClipboardHtml(html) {
  const trimmed = html.trim()
  if (!trimmed) return true

  try {
    const doc = new DOMParser().parseFromString(trimmed, "text/html")
    const body = doc.body
    if (!body) return false
    if (!body.querySelector("img")) return false
    return (body.textContent ?? "").replace(/\s+/g, "").length === 0
  } catch {
    return false
  }
}

/** 画像貼り付けとして扱うか（テキスト貼り付けは CodeMirror の既定動作に任せる） */
function shouldHandleImagePaste(clipboardData) {
  if (!clipboardData) return false

  const files = imageFilesFromClipboard(clipboardData)
  if (files.length === 0) return false

  const html = clipboardHtml(clipboardData).trim()
  if (html && !isImageOnlyClipboardHtml(html)) return false

  const plain = clipboardPlainText(clipboardData).trim()
  if (plain && !looksLikeLocalFilePath(plain)) return false

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
    "previewHost",
    "previewSkinSelect",
    "previewToggle",
    "sourcePane",
    "wysiwygPane",
    "wysiwygHost",
    "editModeTab"
  ]
  static values = {
    labelId: String,
    wikiCompletionsUrl: String,
    wikiLinkLabelsUrl: String,
    tsuzuraAuthorizeUrl: String,
    memoId: String,
    uploadUrl: String
  }

  async connect() {
    if (!this.hasHostTarget || !this.hasFieldTarget) return

    const editorChromePromise = loadEditorChrome()
    const kbmemoEditor = await loadKbmemoEditorExtensions()
    this._resetHostConfig = kbmemoEditor.resetHostConfig
    kbmemoEditor.configureKbmemoHost()

    const editorChrome = await editorChromePromise
    this._insertTextIntoEditorView = editorChrome.insertTextIntoEditorView
    this._promptImageFilename = editorChrome.promptImageFilename

    const [{ EditorView, basicSetup }, { EditorState }] = await Promise.all([
      import("codemirror"),
      import("@codemirror/state")
    ])

    const textarea = this.fieldTarget
    const isNewMemo = !this.memoIdValue
    if (isNewMemo) textarea.value = ""

    this._onResetBody = (event) => {
      const body = event.detail?.body ?? ""
      this.applyExternalBody(body)
    }
    this.element.addEventListener("kbmemo:reset-body-editor", this._onResetBody)
    this._onFlushBody = () => this.flushBodyToField()
    this._onMemoPromoted = (event) => this.applyMemoPromoted(event.detail)
    this.element.addEventListener("kbmemo:flush-body-editor", this._onFlushBody)
    this.element.addEventListener("kbmemo:memo-promoted", this._onMemoPromoted)

    const getWikiConfig = () => ({
      url: this.wikiCompletionsUrlValue,
      memoId: this.memoIdValue || null
    })
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

    if (isNewMemo) textarea.value = ""
    const startDoc = isNewMemo ? "" : textarea.value
    const editorHost = this
    const asciidocExts = await kbmemoEditor.loadAsciidocExtensions({ EditorView })
    this._webPasteHandler = editorChrome.createWebPasteHandler({
      insertText: (text) => this.insertTextAtSelection(text),
    })

    const state = EditorState.create({
      doc: startDoc,
      extensions: [
        basicSetup,
        EditorView.lineWrapping,
        ...asciidocExts,
        kbmemoEditor.listContinuationExtension(),
        ...kbmemoEditor.wikiAutocompletion(getWikiConfig),
        updateListener,
        a11y,
        theme,
        EditorView.domEventHandlers({
          blur: () => this.notifyBodyBlur(),
          keydown(event) {
            return editorHost.handleSourceKeydown(event)
          },
          dragover(event) {
            return editorHost.handleImageDragOver(event)
          },
          drop(event) {
            return editorHost.handleImageDrop(event)
          },
          paste(event) {
            if (editorHost.handleImagePaste(event)) return true
            if (editorHost._webPasteHandler?.(event, editorHost.view)) return true
            return false
          }
        })
      ]
    })

    this.view = new EditorView({
      state,
      parent: this.hostTarget
    })

    const contextMenuTargets = {
      live: {
        container: this.hostTarget,
        getView: () => this.view
      }
    }
    if (this.hasPreviewHostTarget) {
      contextMenuTargets.preview = {
        container: this.previewHostTarget,
        getView: () => this.view
      }
    }
    editorChrome.initEditorContextMenus(contextMenuTargets)

    textarea.addEventListener("change", this._onTextareaExternalChange)

    queueMicrotask(() => {
      this.view?.requestMeasure()
    })

    this._bindDragDrop()
    this._bindPaste()
    this._bindInsertEvent()
    this._editMode = "source"
    this.syncEditModeUi()
    removeLegacyGlobalAsciidoctorStylesheet()
    await this.setupLivePreview(textarea)
    const preferredMode = readEditModePreference()
    if (preferredMode === "wysiwyg" && this.hasWysiwygPaneTarget) {
      await this.switchEditMode("wysiwyg")
    } else {
      this.syncEditModeUi()
    }
    if (isNewMemo) {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => this.focusBodyForEditing())
      })
    }
  }

  focusBodyForEditing() {
    if (this._editMode === "wysiwyg" && this._wysiwygEditor) {
      this._wysiwygEditor.focus({ activate: true })
      return
    }
    this.view?.focus()
  }

  flushBodyToField() {
    if (this._editMode !== "wysiwyg" || !this._wysiwygEditor) return
    const source = this._wysiwygEditor.flush()
    this.syncSourceFromWysiwyg(source)
  }

  applyMemoPromoted(detail) {
    if (!detail) return
    if (detail.id != null) this.memoIdValue = String(detail.id)
    if (detail.tsuzura_authorize_url) {
      this.tsuzuraAuthorizeUrlValue = detail.tsuzura_authorize_url
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
      getSource: () => this.view?.state.doc.toString() ?? textarea.value,
      getWikiConfig: () => ({
        labelsUrl: this.wikiLinkLabelsUrlValue,
        memoId: this.memoIdValue || null,
        tsuzuraAuthorizeUrl: this.hasTsuzuraAuthorizeUrlValue ? this.tsuzuraAuthorizeUrlValue : null,
      }),
    })
  }

  toggleLivePreview(event) {
    this._livePreviewEnabled =
      event?.target?.type === "checkbox" ? event.target.checked : !this._livePreviewEnabled
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
      this.previewToggleTarget.checked = !!this._livePreviewEnabled
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

  editModeTabKeydown(event) {
    const keys = ["ArrowLeft", "ArrowUp", "ArrowRight", "ArrowDown", "Home", "End"]
    if (!keys.includes(event.key)) return

    const tabs = this.editModeTabTargets
    const currentIndex = tabs.indexOf(event.target)
    if (currentIndex < 0) return

    event.preventDefault()
    let nextIndex = currentIndex
    if (event.key === "Home") {
      nextIndex = 0
    } else if (event.key === "End") {
      nextIndex = tabs.length - 1
    } else {
      const step = event.key === "ArrowLeft" || event.key === "ArrowUp" ? -1 : 1
      nextIndex = (currentIndex + step + tabs.length) % tabs.length
    }

    const nextTab = tabs[nextIndex]
    nextTab?.focus()
    const mode = nextTab?.dataset?.editMode
    if (mode === "source" || mode === "wysiwyg") {
      void this.switchEditMode(mode)
    }
  }

  async switchEditMode(mode) {
    if (this._editMode === mode) return

    let flushedSource = null
    if (this._editMode === "wysiwyg") {
      flushedSource = this._wysiwygEditor?.flush() ?? this.fieldTarget.value
    }

    this._editMode = mode
    writeEditModePreference(mode)

    if (flushedSource !== null) {
      this.syncSourceFromWysiwyg(flushedSource)
    }

    if (mode === "wysiwyg") {
      const source = this.view?.state.doc.toString() ?? this.fieldTarget.value
      await this.ensureWysiwygEditor()
      await this._wysiwygEditor.renderFromSource(source)
    }

    this.syncEditModeUi()
  }

  async ensureWysiwygEditor() {
    if (this._wysiwygEditor || !this.hasWysiwygHostTarget) return

    const { createMemoWysiwygEditor } = await import("../adoc_editor/wysiwyg_mount.js")
    this._wysiwygEditor = createMemoWysiwygEditor({
      editorEl: this.wysiwygHostTarget,
      paneEl: this.hasWysiwygPaneTarget ? this.wysiwygPaneTarget : null,
      getMemoId: () => this.memoIdValue || null,
      getWikiConfig: () => ({
        completionsUrl: this.wikiCompletionsUrlValue,
        labelsUrl: this.wikiLinkLabelsUrlValue,
        memoId: this.memoIdValue || null,
        tsuzuraAuthorizeUrl: this.hasTsuzuraAuthorizeUrlValue ? this.tsuzuraAuthorizeUrlValue : null,
      }),
      onSourceChange: (source) => this.syncSourceFromWysiwyg(source),
      onImagePaste: (event) => this.handleImagePaste(event),
    })
  }

  syncSourceFromWysiwyg(source) {
    const textarea = this.fieldTarget
    if (textarea.value !== source) {
      textarea.value = source
      textarea.dispatchEvent(new Event("input", { bubbles: true }))
    }
    // Hidden source CM is synced when leaving WYSIWYG (switchEditMode). Updating it
    // on every WYSIWYG keystroke re-parses the full memo and spuriously warns on
    // table blocks (asciidoctor: unterminated table block) while units stay valid.
    if (this._editMode !== "wysiwyg") {
      this.updateCodeMirrorSource(source)
    }
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
      tab.setAttribute("aria-selected", active ? "true" : "false")
      tab.tabIndex = active ? 0 : -1
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

  canUploadImages() {
    return this.hasUploadUrlValue && this.uploadUrlValue
  }

  disconnect() {
    if (this._onResetBody) {
      this.element.removeEventListener("kbmemo:reset-body-editor", this._onResetBody)
    }
    if (this._onFlushBody) {
      this.element.removeEventListener("kbmemo:flush-body-editor", this._onFlushBody)
    }
    if (this._onMemoPromoted) {
      this.element.removeEventListener("kbmemo:memo-promoted", this._onMemoPromoted)
    }
    this._unbindInsertEvent()
    this._unbindDragDrop()
    this._unbindPaste()
    this.destroySnippetDialog()
    this._resetHostConfig?.()
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

  handleSourceKeydown(event) {
    if (!this.isSnippetShortcut(event)) return false
    event.preventDefault()
    event.stopPropagation()
    this.openSnippetDialog()
    return true
  }

  isSnippetShortcut(event) {
    return (
      this._editMode === "source" &&
      event.key?.toLowerCase() === "k" &&
      event.ctrlKey &&
      !event.metaKey &&
      !event.altKey &&
      !event.shiftKey
    )
  }

  openSnippetDialog() {
    if (!this.view) return
    this.ensureSnippetDialog()
    this._snippetMatches = MEMO_SOURCE_SNIPPETS
    this._snippetActiveIndex = 0
    this.renderSnippetOptions()

    this._snippetSearch.value = ""
    if (typeof this._snippetDialog.showModal === "function") {
      if (!this._snippetDialog.open) this._snippetDialog.showModal()
    } else {
      this._snippetDialog.setAttribute("open", "")
    }

    requestAnimationFrame(() => {
      this._snippetSearch.focus()
    })
  }

  ensureSnippetDialog() {
    if (this._snippetDialog) return

    const dialog = document.createElement("dialog")
    dialog.className = "memo-source-snippet-dialog"
    dialog.setAttribute("closedby", "any")
    dialog.setAttribute("aria-labelledby", "memo-source-snippet-dialog-title")
    dialog.append(this.buildSnippetDialogContent())
    document.body.append(dialog)

    dialog.addEventListener("cancel", (event) => {
      event.preventDefault()
      this.closeSnippetDialog()
    })
    dialog.addEventListener("close", () => {
      if (this._snippetDialogClosing) return
      this.closeSnippetDialog()
    })
    dialog.addEventListener("click", (event) => {
      const target = event.target
      if (target === dialog && this.isSnippetBackdropClick(event)) {
        event.preventDefault()
        this.closeSnippetDialog()
      }
    })

    this._snippetDialog = dialog
  }

  buildSnippetDialogContent() {
    const panel = document.createElement("div")
    panel.className = "memo-source-snippet-panel"

    const header = document.createElement("div")
    header.className = "memo-source-snippet-header"

    const title = document.createElement("strong")
    title.id = "memo-source-snippet-dialog-title"
    title.textContent = "スニペットを挿入"

    const closeButton = document.createElement("button")
    closeButton.type = "button"
    closeButton.className = "memo-source-snippet-close"
    closeButton.setAttribute("aria-label", "閉じる")
    closeButton.textContent = "×"
    closeButton.addEventListener("click", () => this.closeSnippetDialog())
    header.append(title, closeButton)

    const label = document.createElement("label")
    label.className = "memo-source-snippet-search-label"
    label.textContent = "検索"

    const search = document.createElement("input")
    search.type = "search"
    search.className = "memo-source-snippet-search"
    search.autocomplete = "off"
    search.spellcheck = false
    search.setAttribute("aria-controls", "memo-source-snippet-list")
    search.addEventListener("input", () => this.updateSnippetFilter())
    search.addEventListener("keydown", (event) => this.handleSnippetSearchKeydown(event))
    label.append(search)

    const list = document.createElement("div")
    list.id = "memo-source-snippet-list"
    list.className = "memo-source-snippet-list"
    list.setAttribute("role", "listbox")
    list.setAttribute("aria-label", "挿入するスニペット")

    this._snippetSearch = search
    this._snippetList = list

    panel.append(header, label, list)
    return panel
  }

  updateSnippetFilter() {
    this._snippetMatches = filterMemoSourceSnippets(this._snippetSearch?.value ?? "")
    this._snippetActiveIndex = 0
    this.renderSnippetOptions()
  }

  renderSnippetOptions() {
    if (!this._snippetList) return
    this._snippetList.replaceChildren()

    if (!this._snippetMatches?.length) {
      const empty = document.createElement("p")
      empty.className = "memo-source-snippet-empty"
      empty.textContent = "一致するスニペットがありません"
      this._snippetList.append(empty)
      this._snippetSearch?.removeAttribute("aria-activedescendant")
      return
    }

    this._snippetMatches.forEach((snippet, index) => {
      const option = document.createElement("button")
      option.type = "button"
      option.id = `memo-source-snippet-option-${snippet.id}`
      option.className = "memo-source-snippet-option"
      option.setAttribute("role", "option")
      option.tabIndex = -1
      option.setAttribute("aria-selected", index === this._snippetActiveIndex ? "true" : "false")
      option.dataset.snippetIndex = String(index)

      const label = document.createElement("span")
      label.className = "memo-source-snippet-option-label"
      label.textContent = snippet.label
      const detail = document.createElement("code")
      detail.className = "memo-source-snippet-option-detail"
      detail.textContent = snippet.detail
      option.append(label, detail)

      option.addEventListener("mouseenter", () => this.setActiveSnippetIndex(index))
      option.addEventListener("click", () => this.chooseSnippet(index))
      this._snippetList.append(option)
    })

    this.syncSnippetActiveOption()
  }

  handleSnippetSearchKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.closeSnippetDialog()
      return
    }

    if (!this._snippetMatches?.length) return

    if (event.key === "Enter") {
      event.preventDefault()
      this.chooseSnippet(this._snippetActiveIndex)
      return
    }

    const lastIndex = this._snippetMatches.length - 1
    let nextIndex = this._snippetActiveIndex
    if (event.key === "ArrowDown") nextIndex = Math.min(lastIndex, nextIndex + 1)
    else if (event.key === "ArrowUp") nextIndex = Math.max(0, nextIndex - 1)
    else if (event.key === "Home") nextIndex = 0
    else if (event.key === "End") nextIndex = lastIndex
    else return

    event.preventDefault()
    this.setActiveSnippetIndex(nextIndex)
  }

  setActiveSnippetIndex(index) {
    if (!this._snippetMatches?.length) return
    this._snippetActiveIndex = Math.max(0, Math.min(index, this._snippetMatches.length - 1))
    this.syncSnippetActiveOption()
  }

  syncSnippetActiveOption() {
    if (!this._snippetList || !this._snippetSearch) return
    const options = Array.from(this._snippetList.querySelectorAll(".memo-source-snippet-option"))
    for (const [index, option] of options.entries()) {
      const active = index === this._snippetActiveIndex
      option.setAttribute("aria-selected", active ? "true" : "false")
      if (active) {
        this._snippetSearch.setAttribute("aria-activedescendant", option.id)
        option.scrollIntoView({ block: "nearest" })
      }
    }
  }

  chooseSnippet(index) {
    const snippet = this._snippetMatches?.[index]
    if (!snippet || !this.view) return
    this.closeSnippetDialog({ restoreFocus: false })
    applySnippetToEditorView(this.view, snippet)
    this.syncTextareaFromView()
    this._livePreview?.scheduleRender()
  }

  closeSnippetDialog({ restoreFocus = true } = {}) {
    if (!this._snippetDialog) return

    this._snippetDialogClosing = true
    if (this._snippetDialog.open && typeof this._snippetDialog.close === "function") {
      this._snippetDialog.close("close")
    } else {
      this._snippetDialog.removeAttribute("open")
    }
    this._snippetDialogClosing = false
    if (restoreFocus) this.view?.focus()
  }

  destroySnippetDialog() {
    this.closeSnippetDialog({ restoreFocus: false })
    this._snippetDialog?.remove()
    this._snippetDialog = null
    this._snippetSearch = null
    this._snippetList = null
    this._snippetMatches = null
  }

  isSnippetBackdropClick(event) {
    const rect = this._snippetDialog.getBoundingClientRect()
    return (
      event.clientY < rect.top ||
      event.clientY > rect.bottom ||
      event.clientX < rect.left ||
      event.clientX > rect.right
    )
  }

  _onDocumentPaste = (event) => {
    if (!this.isEditorPasteTarget(event)) return
    this.handleImagePaste(event)
  }

  _bindPaste() {
    if (this._pasteBound) return
    document.addEventListener("paste", this._onDocumentPaste, { capture: true })
    this._pasteBound = true
  }

  _unbindPaste() {
    if (!this._pasteBound) return
    document.removeEventListener("paste", this._onDocumentPaste, { capture: true })
    this._pasteBound = false
  }

  isEditorPasteTarget(event) {
    const target = event.target
    if (target instanceof Node && this.element.contains(target)) return true

    const active = document.activeElement
    if (active instanceof Node && this.element.contains(active)) return true

    const anchor = window.getSelection()?.anchorNode
    return anchor instanceof Node && this.element.contains(anchor)
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

    void this.uploadPastedImages(files).catch(() => {
      this.showUploadError("画像の貼り付けに失敗しました")
    })
    return true
  }

  async uploadPastedImages(files) {
    if (!this._promptImageFilename) {
      const editorChrome = await loadEditorChrome()
      this._promptImageFilename = editorChrome.promptImageFilename
    }

    for (const file of files) {
      const { action, filename } = await this._promptImageFilename(suggestedPasteFilename(file))
      if (action !== "upload" || !filename) continue

      await this.uploadFiles([fileWithFilename(file, filename)])
    }
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

  syncTextareaFromView() {
    if (!this.view) return
    const textarea = this.fieldTarget
    const next = this.view.state.doc.toString()
    if (textarea.value !== next) {
      textarea.value = next
      textarea.dispatchEvent(new Event("input", { bubbles: true }))
    }
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

    const token = getCsrfToken()
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
      const text = inserted.join("\n\n")
      if (this._editMode === "wysiwyg" && this._wysiwygEditor?.insertTextAtSelection?.(text)) {
        // カーソル位置へ挿入済み
      } else {
        await this.insertAtCursor(text)
      }
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

  insertTextAtSelection(text) {
    if (this._editMode === "wysiwyg" && this._wysiwygEditor?.insertTextAtSelection?.(text)) {
      return
    }

    if (!this.view) return

    if (this._insertTextIntoEditorView) {
      this._insertTextIntoEditorView(this.view, text)
    } else {
      const { state } = this.view
      const { from, to } = state.selection.main
      this.view.dispatch({
        changes: { from, to, insert: text },
        selection: { anchor: from + text.length, head: from + text.length },
      })
    }

    const textarea = this.fieldTarget
    const next = this.view.state.doc.toString()
    if (textarea.value !== next) {
      textarea.value = next
      textarea.dispatchEvent(new Event("input", { bubbles: true }))
    }
    this._livePreview?.scheduleRender()
  }

  async insertAtCursor(text) {
    if (this._editMode === "wysiwyg" && this._wysiwygEditor) {
      const textarea = this.fieldTarget
      const cur = textarea.value
      const sep = cur.length > 0 && !cur.endsWith("\n") ? "\n\n" : ""
      const next = cur + sep + text
      this.syncSourceFromWysiwyg(next)
      await this._wysiwygEditor.renderFromSource(next)
      this._wysiwygEditor.focus({ activate: true })
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

  applyExternalBody(body) {
    if (this.fieldTarget) this.fieldTarget.value = body
    if (this._editMode === "wysiwyg" && this._wysiwygEditor) {
      const cur = this.view?.state.doc.toString() ?? ""
      const wysiwygMissingUnits =
        this.hasWysiwygHostTarget &&
        !this.wysiwygHostTarget.querySelector(".wysiwyg-unit")
      if (body !== cur || wysiwygMissingUnits) {
        void this._wysiwygEditor.renderFromSource(body)
      }
      return
    }
    if (!this.view) return
    const cur = this.view.state.doc.toString()
    if (body === cur) return
    this.view.dispatch({
      changes: { from: 0, to: cur.length, insert: body }
    })
    this._livePreview?.scheduleRender()
  }

  /** Turbo などで値だけ差し替えた場合 */
  _onTextareaExternalChange = () => {
    this.applyExternalBody(this.fieldTarget.value)
  }
}
