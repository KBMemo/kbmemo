import { Controller } from "@hotwired/stimulus"
import Editor from "svgedit/dist/editor/Editor.js"
import "svgedit/dist/editor/svgedit.css"

const DEFAULT_SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="300" height="300"></svg>'
const DEFAULT_ASSET_BASE = "/svgedit"

export default class extends Controller {
  static targets = ["container", "sourceField"]

  static values = {
    source: String,
    assetBase: { type: String, default: DEFAULT_ASSET_BASE },
  }

  async connect() {
    this.containerTarget.innerHTML =
      '<p class="p-4 text-sm kb-text-muted">SVG エディタを読み込み中…</p>'

    try {
      this.containerTarget.innerHTML = ""
      const base = this.assetBaseValue.replace(/\/\z/, "")

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
      this.containerTarget.innerHTML =
        '<p class="p-4 text-sm text-red-600">SVG エディタの読み込みに失敗しました。</p>'
    }
  }

  disconnect() {
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
