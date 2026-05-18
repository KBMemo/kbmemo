import { Controller } from "@hotwired/stimulus"
import { diagramLanguageExtensions } from "../memo_diagram_editor/language_extensions"

export default class extends Controller {
  static targets = ["field", "host"]

  static values = {
    engine: String
  }

  async connect() {
    if (!this.hasHostTarget || !this.hasFieldTarget) return

    const [{ EditorView, basicSetup }, { EditorState }] = await Promise.all([
      import("codemirror"),
      import("@codemirror/state")
    ])

    const languageExtensions = await diagramLanguageExtensions(this.engineValue)

    const theme = EditorView.theme({
      "&": {
        fontSize: "13px",
        minHeight: "100%",
        fontFamily:
          'ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace'
      },
      ".cm-scroller": { overflow: "auto" },
      ".cm-content": {
        paddingBlock: "0.75rem",
        paddingLeft: "1rem",
        paddingRight: "1rem"
      },
      ".cm-gutters": { backgroundColor: "#fafafa", borderRight: "1px solid #e4e4e7" }
    })

    const state = EditorState.create({
      doc: this.fieldTarget.value,
      extensions: [
        basicSetup,
        ...languageExtensions,
        EditorState.readOnly.of(true),
        EditorView.editable.of(false),
        theme
      ]
    })

    this._view = new EditorView({ state, parent: this.hostTarget })
  }

  disconnect() {
    this._view?.destroy()
    this._view = null
  }
}
