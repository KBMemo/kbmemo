import { Controller } from "@hotwired/stimulus"

function clamp(n, min, max) {
  return Math.min(max, Math.max(min, n))
}

export default class extends Controller {
  static targets = ["stage", "image", "scaleLabel"]

  static values = {
    src: String
  }

  connect() {
    this.scale = 1
    this.panX = 0
    this.panY = 0
    this.minScale = 0.1
    this.maxScale = 12
    this._dragging = false
    this._onImageLoad = () => this.fitToWindow()
    this.imageTarget.addEventListener("load", this._onImageLoad)
    if (this.imageTarget.complete) this.fitToWindow()
    this._onResize = () => {
      if (this._fitMode) this.fitToWindow()
      else this._clampPan()
    }
    window.addEventListener("resize", this._onResize)
    this._applyTransform()
  }

  disconnect() {
    this.imageTarget.removeEventListener("load", this._onImageLoad)
    window.removeEventListener("resize", this._onResize)
    this._endDrag()
  }

  zoomIn() {
    this._fitMode = false
    this.setScale(this.scale * 1.2)
  }

  zoomOut() {
    this._fitMode = false
    this.setScale(this.scale / 1.2)
  }

  resetZoom() {
    this._fitMode = false
    this.resetPan()
    this.setScale(1)
  }

  fitToWindow() {
    this._fitMode = true
    this.resetPan()
    const img = this.imageTarget
    const stage = this.stageTarget
    const iw = img.naturalWidth
    const ih = img.naturalHeight
    if (!iw || !ih) return

    const pad = 32
    const cw = Math.max(120, stage.clientWidth - pad)
    const ch = Math.max(120, stage.clientHeight - pad)
    this.setScale(clamp(Math.min(cw / iw, ch / ih), this.minScale, this.maxScale))
  }

  wheel(event) {
    this._fitMode = false
    const factor = event.deltaY < 0 ? 1.1 : 1 / 1.1
    this.setScale(this.scale * factor)
  }

  pointerDown(event) {
    if (!this._canPan()) return
    if (event.pointerType === "mouse" && event.button !== 0) return

    event.preventDefault()
    this._dragging = true
    this._dragPointerId = event.pointerId
    this._dragStartX = event.clientX
    this._dragStartY = event.clientY
    this._panStartX = this.panX
    this._panStartY = this.panY
    this.stageTarget.classList.add("is-panning")
    this.stageTarget.classList.remove("can-pan")

    try {
      this.stageTarget.setPointerCapture(event.pointerId)
    } catch {
      /* ignore */
    }
  }

  pointerMove(event) {
    if (!this._dragging || event.pointerId !== this._dragPointerId) return

    this.panX = this._panStartX + (event.clientX - this._dragStartX)
    this.panY = this._panStartY + (event.clientY - this._dragStartY)
    this._clampPan()
    this._applyTransform()
  }

  pointerUp(event) {
    if (!this._dragging || event.pointerId !== this._dragPointerId) return
    this._endDrag()
  }

  setScale(next) {
    this.scale = clamp(next, this.minScale, this.maxScale)
    this._clampPan()
    this._applyTransform()
    if (this.hasScaleLabelTarget) {
      this.scaleLabelTarget.textContent = `${Math.round(this.scale * 100)}%`
    }
  }

  resetPan() {
    this.panX = 0
    this.panY = 0
  }

  _applyTransform() {
    this.imageTarget.style.transform = `translate(${this.panX}px, ${this.panY}px) scale(${this.scale})`
    this.imageTarget.style.transformOrigin = "center center"
    this._updatePanCursor()
  }

  _canPan() {
    const img = this.imageTarget
    const stage = this.stageTarget
    if (!img.complete || !img.naturalWidth) return false

    const layoutW = img.offsetWidth
    const layoutH = img.offsetHeight
    const visualW = layoutW * this.scale
    const visualH = layoutH * this.scale
    const pad = 2
    return visualW > stage.clientWidth + pad || visualH > stage.clientHeight + pad
  }

  _clampPan() {
    const img = this.imageTarget
    const stage = this.stageTarget
    const layoutW = img.offsetWidth
    const layoutH = img.offsetHeight
    const visualW = layoutW * this.scale
    const visualH = layoutH * this.scale
    const sw = stage.clientWidth
    const sh = stage.clientHeight

    if (visualW <= sw && visualH <= sh) {
      this.panX = 0
      this.panY = 0
      return
    }

    const maxX = Math.max(0, (visualW - sw) / 2)
    const maxY = Math.max(0, (visualH - sh) / 2)
    this.panX = clamp(this.panX, -maxX, maxX)
    this.panY = clamp(this.panY, -maxY, maxY)
  }

  _updatePanCursor() {
    if (this._dragging) return
    this.stageTarget.classList.toggle("can-pan", this._canPan())
  }

  _endDrag() {
    if (!this._dragging) return
    this._dragging = false
    this._dragPointerId = null
    this.stageTarget.classList.remove("is-panning")
    this._updatePanCursor()
  }
}
