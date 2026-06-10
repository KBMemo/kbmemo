import { Controller } from "@hotwired/stimulus"

const DEFAULT_SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="300" height="300"></svg>'
const DEFAULT_ASSET_BASE = "/svgedit"
let svgEditorAssetsPromise = null

function loadSvgEditorAssets() {
  svgEditorAssetsPromise ??= Promise.all([
    import("svgedit/dist/editor/Editor.js"),
    import("svgedit/dist/editor/svgedit.css"),
  ]).then(([editorModule]) => editorModule.default)
  return svgEditorAssetsPromise
}

function statusMessage(className, message) {
  const element = document.createElement("p")
  element.className = className
  element.textContent = message
  return element
}

export default class extends Controller {
  static targets = ["container", "sourceField"]

  static values = {
    source: String,
    assetBase: { type: String, default: DEFAULT_ASSET_BASE },
  }

  async connect() {
    this.disconnected = false
    if (this.hasSourceFieldTarget) {
      this.sourceFieldTarget.value = this.sourceValue?.trim() || DEFAULT_SVG
    }

    this.containerTarget.replaceChildren(
      statusMessage("p-4 text-sm kb-text-muted", "SVG エディタを読み込み中…")
    )

    try {
      const Editor = await loadSvgEditorAssets()
      if (this.disconnected) return

      this.containerTarget.replaceChildren()
      const base = this.assetBaseValue.replace(/\/$/, "")

      this.editor = new Editor(this.containerTarget)
      this.editor.setConfig({
        allowInitialUserOverride: true,
        noDefaultExtensions: false,
        imgPath: `${base}/images`,
        extPath: `${base}/extensions`,
      })
      await this.editor.init()

      const svg = this.sourceValue?.trim() || DEFAULT_SVG
      if (this.editor.svgCanvas.setSvgString(svg) === false) {
        this.editor.svgCanvas.setSvgString(DEFAULT_SVG)
      }
      this.scheduleResize()
      this.resizeObserver = new ResizeObserver(() => this.scheduleResize())
      this.resizeObserver.observe(this.containerTarget)
    } catch (error) {
      console.error("SVGEdit init failed", error)
      this.containerTarget.replaceChildren(
        statusMessage("p-4 text-sm kb-text-danger", "SVG エディタの読み込みに失敗しました。")
      )
    }
  }

  disconnect() {
    this.disconnected = true
    this.resizeObserver?.disconnect()
  }

  scheduleResize() {
    window.requestAnimationFrame(() => {
      window.dispatchEvent(new Event("resize"))
    })
  }

  beforeSubmit() {
    if (!this.editor?.svgCanvas || !this.hasSourceFieldTarget) return
    this.sourceFieldTarget.value = this.editor.svgCanvas.getSvgString()
  }
}
