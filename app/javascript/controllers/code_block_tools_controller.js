import { Controller } from "@hotwired/stimulus"

// メモ表示のコードブロック（.listingblock）にツールバーを付与する。
// - すべての source ブロックに言語バッジ + コピーボタン
// - plantuml / mermaid ブロックには「図 ⇄ ソース」トグル（Kroki プロキシで遅延描画）
// - svg ブロックには「画像 ⇄ ソース」トグル（サーバー側サニタイズ）
const DIAGRAM_LANGS = new Set(["plantuml", "puml", "uml", "mermaid"])
const TOGGLE_LANGS = new Set([...DIAGRAM_LANGS, "svg"])

function toggleLabels(lang) {
  if (lang === "svg") {
    return {
      display: "画像",
      displayTitle: "画像として表示",
      loading: "読み込み中…",
      errorFallback: "画像の表示に失敗しました。",
    }
  }
  return {
    display: "図",
    displayTitle: "図として表示",
    loading: "図を生成中…",
    errorFallback: "図の生成に失敗しました。",
  }
}

const COPY_ICON = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>`
const CHECK_ICON = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="20 6 9 17 4 12"></polyline></svg>`

export default class extends Controller {
  static values = {
    renderUrl: String,
    svgEditUrl: String,
  }

  connect() {
    this.decorate()
  }

  decorate() {
    let svgBlockIndex = 0

    this.element.querySelectorAll(".listingblock").forEach((block) => {
      if (block.dataset.codeToolsReady === "1") return
      const content = block.querySelector(":scope > .content")
      const code = content?.querySelector("pre code, code")
      if (!content || !code) return

      block.dataset.codeToolsReady = "1"
      const lang = (code.getAttribute("data-lang") || "").trim().toLowerCase()
      block.classList.add("has-code-tools")

      const toolbar = document.createElement("div")
      toolbar.className = "kb-code-toolbar"

      if (lang) {
        const badge = document.createElement("span")
        badge.className = "kb-code-lang"
        badge.textContent = lang
        toolbar.appendChild(badge)
      }

      if (this.hasRenderUrlValue && TOGGLE_LANGS.has(lang)) {
        toolbar.appendChild(this.buildToggleButton(block, content, code, lang))
      }

      if (lang === "svg" && this.hasSvgEditUrlValue) {
        toolbar.appendChild(this.buildSvgEditLink(svgBlockIndex))
        svgBlockIndex += 1
      }

      toolbar.appendChild(this.buildCopyButton(code))
      content.insertBefore(toolbar, content.firstChild)
    })
  }

  buildSvgEditLink(index) {
    const link = document.createElement("a")
    link.className = "kb-code-btn kb-code-edit"
    link.textContent = "編集"
    link.title = "SVG を編集"
    link.href = this.svgEditUrlValue.replace("__INDEX__", String(index))
    link.target = "_blank"
    link.rel = "noopener"
    return link
  }

  buildCopyButton(code) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "kb-code-btn kb-code-copy"
    button.title = "コードをコピー"
    button.setAttribute("aria-label", "コードをコピー")
    button.innerHTML = COPY_ICON
    button.addEventListener("click", () => this.copy(code, button))
    return button
  }

  async copy(code, button) {
    const text = code.textContent ?? ""
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text)
      } else {
        this.legacyCopy(text)
      }
      this.flash(button)
    } catch {
      this.legacyCopy(text)
      this.flash(button)
    }
  }

  legacyCopy(text) {
    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.style.position = "absolute"
    area.style.left = "-9999px"
    document.body.appendChild(area)
    area.select()
    try {
      document.execCommand("copy")
    } finally {
      area.remove()
    }
  }

  flash(button) {
    button.classList.add("is-copied")
    button.innerHTML = CHECK_ICON
    window.clearTimeout(button._copyTimer)
    button._copyTimer = window.setTimeout(() => {
      button.classList.remove("is-copied")
      button.innerHTML = COPY_ICON
    }, 1200)
  }

  buildToggleButton(block, content, code, lang) {
    const labels = toggleLabels(lang)
    const button = document.createElement("button")
    button.type = "button"
    button.className = "kb-code-btn kb-code-toggle"
    button.dataset.mode = "source"
    button.textContent = labels.display
    button.title = labels.displayTitle

    const pre = content.querySelector(":scope > pre")
    const figure = document.createElement("div")
    figure.className = "kb-code-diagram"
    figure.hidden = true
    content.appendChild(figure)

    const state = { rendered: false, loading: false }

    button.addEventListener("click", async () => {
      await this.toggleDiagram(button, content, code, lang, figure, pre, state, labels)
    })

    if (lang === "svg") {
      queueMicrotask(() => {
        this.showDiagramInitially(button, content, code, lang, figure, pre, state, labels)
      })
    }

    return button
  }

  async showDiagramInitially(button, content, code, lang, figure, pre, state, labels) {
    if (pre) pre.hidden = true
    const ok = await this.renderInto(figure, code, lang, state, button, labels)
    if (ok) {
      figure.hidden = false
      button.dataset.mode = "diagram"
      button.textContent = "ソース"
      button.title = "ソースを表示"
      return
    }

    figure.hidden = false
    if (pre) pre.hidden = false
    button.dataset.mode = "source"
    button.textContent = labels.display
    button.title = labels.displayTitle
  }

  async toggleDiagram(button, content, code, lang, figure, pre, state, labels) {
    const showingSource = button.dataset.mode === "source"
    if (showingSource) {
      if (state.loading) return
      if (!state.rendered) {
        const ok = await this.renderInto(figure, code, lang, state, button, labels)
        if (!ok) {
          // 失敗時はソースを残したままエラーを表示（再クリックで再試行）。
          figure.hidden = false
          if (pre) pre.hidden = false
          return
        }
      }
      if (pre) pre.hidden = true
      figure.hidden = false
      button.dataset.mode = "diagram"
      button.textContent = "ソース"
      button.title = "ソースを表示"
    } else {
      figure.hidden = true
      if (pre) pre.hidden = false
      button.dataset.mode = "source"
      button.textContent = labels.display
      button.title = labels.displayTitle
    }
  }

  async renderInto(figure, code, lang, state, button, labels) {
    state.loading = true
    button.disabled = true
    figure.hidden = false
    figure.replaceChildren(this.statusNode(labels.loading))

    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    try {
      const res = await fetch(this.renderUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": token,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({ engine: lang, source: code.textContent ?? "" }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok && data.svg) {
        this.replaceWithSanitizedSvg(figure, data.svg)
        state.rendered = true
        return true
      }
      figure.replaceChildren(this.errorNode(data.error || labels.errorFallback))
      return false
    } catch {
      figure.replaceChildren(this.errorNode(lang === "svg" ? "画像の表示に失敗しました。" : "Kroki に接続できませんでした。"))
      return false
    } finally {
      state.loading = false
      button.disabled = false
    }
  }

  replaceWithSanitizedSvg(figure, sanitizedSvg) {
    // render_diagram returns only server-sanitized SVG from MemoDiagramRenderer.
    figure.innerHTML = sanitizedSvg
  }

  statusNode(message) {
    const span = document.createElement("span")
    span.className = "kb-code-diagram-status"
    span.textContent = message
    return span
  }

  errorNode(message) {
    const span = document.createElement("span")
    span.className = "kb-code-diagram-error"
    span.textContent = message
    return span
  }
}
