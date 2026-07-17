import { Controller } from "@hotwired/stimulus"

function clamp(n, min, max) {
  return Math.min(max, Math.max(min, n))
}

export default class extends Controller {
  static targets = [
    "shell",
    "body",
    "toggleButton",
    "toggleButtonMobile",
    "toggleGlyph",
    "toggleGlyphMobile",
    "toggleLabelMobile",
    "resizer"
  ]
  static values = {
    storageKey: { type: String, default: "kbmemo_memo_sidebar_v1" }
  }

  connect() {
    this._dragging = false
    this._activePointerId = null
    this._onPointerMove = (e) => this._dragMove(e)
    this._onPointerUp = () => this._dragEnd()
    this._onResize = () => this._applyLayout()
    this._width = 320
    this._collapsed = false
    this._readPrefs()
    this._applyLayout()
    window.addEventListener("resize", this._onResize)
    if (this.hasShellTarget && typeof ResizeObserver !== "undefined") {
      this._shellResizeObserver = new ResizeObserver(() => this._positionToggleButton())
      this._shellResizeObserver.observe(this.shellTarget)
    }
  }

  disconnect() {
    window.removeEventListener("resize", this._onResize)
    this._shellResizeObserver?.disconnect()
    if (this._dragging) {
      this._dragging = false
      this._detachDragListeners()
      this._writePrefs()
    }
    document.body.style.cursor = ""
    document.body.style.userSelect = ""
  }

  toggle() {
    this._collapsed = !this._collapsed
    this._writePrefs()
    this._applyLayout()
  }

  resizerPointerDown(event) {
    if (this._collapsed) return
    if (!window.matchMedia("(min-width: 768px)").matches) return
    if (event.pointerType === "mouse" && event.button !== 0) return
    event.preventDefault()
    if (!this.hasResizerTarget || !this.hasShellTarget) return

    this._dragging = true
    this._activePointerId = event.pointerId
    document.body.style.cursor = "col-resize"
    document.body.style.userSelect = "none"

    try {
      this.resizerTarget.setPointerCapture(event.pointerId)
    } catch {
      /* ignore */
    }
    this.resizerTarget.addEventListener("pointermove", this._onPointerMove)
    this.resizerTarget.addEventListener("pointerup", this._onPointerUp)
    this.resizerTarget.addEventListener("pointercancel", this._onPointerUp)
  }

  resizerKeydown(event) {
    if (this._collapsed || !window.matchMedia("(min-width: 768px)").matches) return

    const step = event.shiftKey ? 50 : 20
    let nextWidth = null

    switch (event.key) {
      case "ArrowLeft":
        nextWidth = this._width - step
        break
      case "ArrowRight":
        nextWidth = this._width + step
        break
      case "Home":
        nextWidth = this._minWidth()
        break
      case "End":
        nextWidth = this._maxWidth()
        break
      default:
        return
    }

    event.preventDefault()
    this._width = clamp(nextWidth, this._minWidth(), this._maxWidth())
    this._writePrefs()
    this._applyLayout()
  }

  _readPrefs() {
    try {
      const raw = localStorage.getItem(this.storageKeyValue)
      if (!raw) return
      const j = JSON.parse(raw)
      if (Number.isFinite(j.width)) this._width = j.width
      if (typeof j.collapsed === "boolean") this._collapsed = j.collapsed
    } catch {
      /* ignore */
    }
  }

  _writePrefs() {
    try {
      localStorage.setItem(
        this.storageKeyValue,
        JSON.stringify({ width: this._width, collapsed: this._collapsed })
      )
    } catch {
      /* ignore */
    }
  }

  _detachDragListeners() {
    if (!this.hasResizerTarget) return
    this.resizerTarget.removeEventListener("pointermove", this._onPointerMove)
    this.resizerTarget.removeEventListener("pointerup", this._onPointerUp)
    this.resizerTarget.removeEventListener("pointercancel", this._onPointerUp)
    if (this._activePointerId != null) {
      try {
        this.resizerTarget.releasePointerCapture(this._activePointerId)
      } catch {
        /* ignore */
      }
    }
    this._activePointerId = null
    document.body.style.cursor = ""
    document.body.style.userSelect = ""
  }

  _minWidth() {
    return 220
  }

  _maxWidth() {
    return Math.min(Math.floor(window.innerWidth * 0.55), 560)
  }

  _updateResizerA11y() {
    if (!this.hasResizerTarget) return

    const enabled = !this._collapsed && window.matchMedia("(min-width: 768px)").matches
    this.resizerTarget.tabIndex = enabled ? 0 : -1
    this.resizerTarget.setAttribute("aria-disabled", String(!enabled))
    this.resizerTarget.setAttribute("aria-valuemin", String(this._minWidth()))
    this.resizerTarget.setAttribute("aria-valuemax", String(this._maxWidth()))
    this._updateResizerValueA11y()
  }

  _updateResizerValueA11y() {
    if (!this.hasResizerTarget) return

    const width = Math.round(this._width)
    this.resizerTarget.setAttribute("aria-valuenow", String(width))
    this.resizerTarget.setAttribute("aria-valuetext", `幅 ${width} ピクセル`)
  }

  _dragMove(event) {
    if (!this._dragging || !this.hasShellTarget) return
    const left = this.shellTarget.getBoundingClientRect().left
    const maxPx = this._maxWidth()
    this._width = clamp(event.clientX - left, this._minWidth(), maxPx)
    this.shellTarget.style.width = `${this._width}px`
    this.shellTarget.style.maxWidth = `${maxPx}px`
    this._updateResizerValueA11y()
    this._positionToggleButton()
  }

  _dragEnd() {
    if (!this._dragging) return
    this._dragging = false
    this._detachDragListeners()
    this._writePrefs()
    this._applyLayout()
  }

  _applyLayout() {
    if (!this.hasShellTarget) return

    const md = window.matchMedia("(min-width: 768px)").matches

    if (md) {
      const maxPx = this._maxWidth()
      if (this._collapsed) {
        this.shellTarget.style.flexBasis = "0"
        this.shellTarget.style.width = "0"
        this.shellTarget.style.minWidth = "0"
        this.shellTarget.style.maxWidth = "0"
        this.shellTarget.style.maxHeight = ""
        this.shellTarget.style.borderWidth = "0"
        this.shellTarget.style.overflow = "hidden"
        if (this.hasBodyTarget) this.bodyTarget.classList.add("hidden")
        if (this.hasResizerTarget) {
          this.resizerTarget.classList.add("pointer-events-none", "opacity-40")
        }
      } else {
        this._width = clamp(this._width, this._minWidth(), maxPx)
        this.shellTarget.style.flexBasis = ""
        this.shellTarget.style.width = `${this._width}px`
        this.shellTarget.style.minWidth = ""
        this.shellTarget.style.maxWidth = `${maxPx}px`
        this.shellTarget.style.borderWidth = ""
        this.shellTarget.style.overflow = "hidden"
        this._applyShellMaxHeight()
        if (this.hasBodyTarget) this.bodyTarget.classList.remove("hidden")
        if (this.hasResizerTarget) {
          this.resizerTarget.classList.remove("pointer-events-none", "opacity-40")
        }
      }
    } else {
      this.shellTarget.style.width = ""
      this.shellTarget.style.minWidth = ""
      this.shellTarget.style.maxWidth = ""
      this.shellTarget.style.flexBasis = ""
      if (this._collapsed) {
        this.shellTarget.style.borderWidth = "0"
        this.shellTarget.style.overflow = "hidden"
        this.shellTarget.style.maxHeight = "3rem"
        if (this.hasBodyTarget) this.bodyTarget.classList.add("hidden")
      } else {
        this.shellTarget.style.borderWidth = ""
        this.shellTarget.style.overflow = "hidden"
        this.shellTarget.style.maxHeight = "min(42vh, 360px)"
        if (this.hasBodyTarget) this.bodyTarget.classList.remove("hidden")
      }
      if (this.hasResizerTarget) {
        this.resizerTarget.classList.remove("pointer-events-none", "opacity-40")
      }
    }

    this._updateToggleUi()
    this._updateResizerA11y()
    this._positionToggleButton()
  }

  // サイドバー下端がビューポート外に出て最終行が欠けるのを防ぐ
  _applyShellMaxHeight() {
    if (!this.hasShellTarget) return

    const top = this.shellTarget.getBoundingClientRect().top
    const available = Math.floor(window.innerHeight - top)
    if (available > 0) {
      this.shellTarget.style.maxHeight = `${available}px`
    } else {
      this.shellTarget.style.maxHeight = ""
    }
  }

  _positionToggleButton() {
    if (!this.hasToggleButtonTarget || !this.hasShellTarget) return

    const btn = this.toggleButtonTarget
    if (!window.matchMedia("(min-width: 768px)").matches) {
      btn.style.left = ""
      btn.style.top = ""
      btn.style.transform = ""
      return
    }

    const shellRect = this.shellTarget.getBoundingClientRect()
    const resizerWidth = this.hasResizerTarget ? this.resizerTarget.offsetWidth : 0
    const edgeX = shellRect.right + resizerWidth / 2

    btn.style.left = `${edgeX}px`
    btn.style.top = "50vh"
    btn.style.transform = "translate(-50%, -50%)"
  }

  _updateToggleUi() {
    const c = this._collapsed
    const expanded = !c
    const glyph = c ? "»»" : "««"
    const label = c ? "展開" : "折りたたむ"
    const title = c ? "メモ一覧サイドバーを展開" : "メモ一覧サイドバーを折りたたむ"

    if (this.hasToggleButtonTarget) {
      this.toggleButtonTarget.setAttribute("aria-expanded", String(expanded))
      this.toggleButtonTarget.title = title
    }
    if (this.hasToggleButtonMobileTarget) {
      this.toggleButtonMobileTarget.setAttribute("aria-expanded", String(expanded))
    }
    if (this.hasToggleGlyphTarget) {
      this.toggleGlyphTarget.textContent = glyph
    }
    if (this.hasToggleGlyphMobileTarget) {
      this.toggleGlyphMobileTarget.textContent = glyph
    }
    if (this.hasToggleLabelMobileTarget) {
      this.toggleLabelMobileTarget.textContent = label
    }
  }
}
