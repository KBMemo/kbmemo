import { Controller } from "@hotwired/stimulus"
import { asciidocExtensions } from "../memo_body_editor/asciidoc_extensions"
import { wikiAutocompletion } from "../memo_body_editor/wiki_completion"
import { listContinuationExtension } from "../memo_body_editor/list_continuation"
import { tableWysiwygFieldExtension } from "../memo_body_editor/table_wysiwyg_field"
import { imageWysiwygExtension } from "../memo_body_editor/image_wysiwyg"
import { wysiwygLiteExtension } from "../memo_body_editor/wysiwyg_lite"
import { wikiLinkWysiwygExtension } from "../memo_body_editor/wiki_link_wysiwyg"

// 本文 textarea（送信・memo-draft の参照用）と CodeMirror を同期する。
// CodeMirror は動的 import で初回のみ別チャンク読み込み。
export default class extends Controller {
  static targets = ["field", "host", "imageInput", "uploadError"]
  static values = {
    labelId: String,
    wikiCompletionsUrl: String,
    wikiLinkLabelsUrl: String,
    memoId: String,
    uploadUrl: String
  }

  async connect() {
    if (!this.hasHostTarget || !this.hasFieldTarget) return

    const [{ EditorView, basicSetup }, { EditorState }] = await Promise.all([
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

    const state = EditorState.create({
      doc: startDoc,
      extensions: [
        basicSetup,
        EditorView.lineWrapping,
        ...asciidocExtensions(),
        wysiwygLiteExtension(),
        imageWysiwygExtension(getMemoId),
        ...tableWysiwygFieldExtension(),
        listContinuationExtension(),
        ...wikiLinkWysiwygExtension(getWikiLabelsConfig),
        ...wikiAutocompletion(getWikiConfig),
        updateListener,
        a11y,
        theme,
        EditorView.domEventHandlers({
          blur: () => this.notifyBodyBlur()
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
  }

  disconnect() {
    if (this.fieldTarget && this._onTextareaExternalChange) {
      this.fieldTarget.removeEventListener("change", this._onTextareaExternalChange)
    }
    if (this.view) {
      this.view.destroy()
      this.view = null
    }
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

    const files = Array.from(input.files ?? [])
    if (files.length === 0) return

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

    input.value = ""

    if (inserted.length > 0) {
      await this.insertAtCursor(inserted.join("\n\n"))
    }

    if (failed) {
      const suffix =
        inserted.length > 0 ? `（${inserted.length} 件は挿入済み）` : ""
      this.showUploadError(`${failed}${suffix}`)
    }
  }

  async insertAtCursor(text) {
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
    this.view.dispatch({
      changes: { from: 0, to: cur.length, insert: next }
    })
  }
}
