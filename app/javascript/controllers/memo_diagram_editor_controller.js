import { Controller } from "@hotwired/stimulus"
import { diagramLanguageExtensions } from "../memo_diagram_editor/language_extensions"
import { renderSvgInPreviewPanel } from "../memo_diagram_editor/preview_panel"

const PREVIEW_DEBOUNCE_MS = 500

// ダイアグラム専用編集: textarea（送信）と CodeMirror を同期。Kroki プレビューは debounce 付き POST。
export default class extends Controller {
  static targets = ["field", "host", "preview", "previewLoading", "previewError"]
  static values = { engine: String, previewUrl: String }

  async connect() {
    if (!this.hasHostTarget || !this.hasFieldTarget) return

    const [{ EditorView, basicSetup }, { EditorState }] = await Promise.all([
      import("codemirror"),
      import("@codemirror/state")
    ])

    const textarea = this.fieldTarget
    const languageExtensions = await diagramLanguageExtensions(this.engineValue)

    const updateListener = EditorView.updateListener.of((vu) => {
      if (vu.docChanged) {
        const next = vu.state.doc.toString()
        if (textarea.value !== next) {
          textarea.value = next
          textarea.dispatchEvent(new Event("input", { bubbles: true }))
        }
        this.schedulePreview(next)
      }
    })

    const a11y = EditorView.contentAttributes.of({
      role: "textbox",
      "aria-multiline": "true",
      "aria-labelledby": "diagram-source-label"
    })

    const theme = EditorView.theme({
      "&": {
        fontSize: "13px",
        minHeight: "24rem",
        fontFamily:
          'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace',
        borderRadius: "0",
        outline: "none"
      },
      "&.cm-editor.cm-focused": { outline: "none" },
      ".cm-editor": {
        outline: "none",
        borderRadius: "0",
        backgroundColor: "#fff"
      },
      ".cm-line": { padding: "0", lineHeight: "1.625" },
      ".cm-content": {
        caretColor: "#18181b",
        paddingBlock: "0.5rem",
        paddingLeft: "0.75rem",
        paddingRight: "0.75rem",
        color: "#18181b",
        cursor: "text"
      },
      ".cm-cursor, .cm-dropCursor": {
        borderLeftWidth: "2px",
        borderLeftColor: "#18181b"
      },
      ".cm-selectionBackground": { background: "#bbf7d066" },
      ".cm-focused .cm-selectionBackground": { background: "#86efacb3" },
      ".cm-activeLine": { background: "#fafafa" },
      ".cm-scroller": {
        overflow: "auto",
        fontFamily: "inherit",
        lineHeight: "inherit"
      },
      ".cm-gutters": {
        flexShrink: "0",
        borderRight: "1px solid #e4e4e7",
        backgroundColor: "#fafafa",
        color: "#71717a",
        borderRadius: "0"
      },
      ".cm-gutters.cm-lineNumbers": {
        minWidth: "2.75rem",
        paddingRight: "0.5rem"
      },
      ".cm-lineNumbers .cm-gutterElement": {
        minWidth: "2ch",
        padding: "0 0.25rem 0 0",
        textAlign: "right"
      }
    })

    const state = EditorState.create({
      doc: textarea.value,
      extensions: [
        basicSetup,
        EditorView.lineWrapping,
        ...languageExtensions,
        updateListener,
        a11y,
        theme
      ]
    })

    this.view = new EditorView({
      state,
      parent: this.hostTarget
    })

    textarea.addEventListener("change", this._onTextareaExternalChange)

    queueMicrotask(() => {
      this.view?.requestMeasure()
      if (this.hasPreviewUrlValue) {
        this.schedulePreview(textarea.value)
      }
    })
  }

  disconnect() {
    this._clearPreviewTimer()
    this._abortPreview()
    this._revokePreviewUrl()
    if (this.fieldTarget && this._onTextareaExternalChange) {
      this.fieldTarget.removeEventListener("change", this._onTextareaExternalChange)
    }
    if (this.view) {
      this.view.destroy()
      this.view = null
    }
  }

  schedulePreview(source) {
    if (!this.hasPreviewUrlValue) return
    this._clearPreviewTimer()
    this._previewTimer = window.setTimeout(() => {
      void this.fetchPreview(source)
    }, PREVIEW_DEBOUNCE_MS)
  }

  async fetchPreview(source) {
    if (!this.hasPreviewUrlValue) return

    this._abortPreview()
    this._previewAbort = new AbortController()
    const signal = this._previewAbort.signal

    this.setPreviewLoading(true)
    this.clearPreviewError()

    const token = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          ...(token ? { "X-CSRF-Token": token } : {})
        },
        body: JSON.stringify({ source }),
        signal
      })

      const data = await response.json()

      if (!response.ok) {
        this.showPreviewError(data.error || "プレビューを生成できませんでした")
        this.clearPreviewSvg()
        return
      }

      if (!data.svg) {
        this.showPreviewError("プレビューを生成できませんでした")
        this.clearPreviewSvg()
        return
      }

      this.renderPreviewSvg(data.svg)
    } catch (error) {
      if (error.name === "AbortError") return
      this.showPreviewError("プレビューの取得に失敗しました")
      this.clearPreviewSvg()
    } finally {
      if (!signal.aborted) {
        this.setPreviewLoading(false)
      }
    }
  }

  renderPreviewSvg(svg) {
    if (!this.hasPreviewTarget) return
    this._revokePreviewUrl()
    this._revokePreview = renderSvgInPreviewPanel(this.previewTarget, svg)
  }

  clearPreviewSvg() {
    if (!this.hasPreviewTarget) return
    this._revokePreviewUrl()
    this.previewTarget.replaceChildren()
  }

  setPreviewLoading(loading) {
    if (!this.hasPreviewLoadingTarget) return
    this.previewLoadingTarget.classList.toggle("hidden", !loading)
  }

  showPreviewError(message) {
    if (!this.hasPreviewErrorTarget) return
    this.previewErrorTarget.textContent = message
    this.previewErrorTarget.classList.remove("hidden")
  }

  clearPreviewError() {
    if (!this.hasPreviewErrorTarget) return
    this.previewErrorTarget.textContent = ""
    this.previewErrorTarget.classList.add("hidden")
  }

  _clearPreviewTimer() {
    if (this._previewTimer != null) {
      window.clearTimeout(this._previewTimer)
      this._previewTimer = null
    }
  }

  _abortPreview() {
    this._previewAbort?.abort()
    this._previewAbort = null
  }

  _revokePreviewUrl() {
    this._revokePreview?.()
    this._revokePreview = null
  }

  _onTextareaExternalChange = () => {
    if (!this.view) return
    const next = this.fieldTarget.value
    const cur = this.view.state.doc.toString()
    if (next === cur) return
    this.view.dispatch({
      changes: { from: 0, to: cur.length, insert: next }
    })
    this.schedulePreview(next)
  }
}
