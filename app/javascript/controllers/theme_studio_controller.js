import { Controller } from "@hotwired/stimulus"
import {
  applyTheme,
  applyThemePreview,
  createCustomTheme,
  deleteCustomTheme,
  findCustomTheme,
  getStoredThemeId,
  getThemeTokenDefaults,
  loadThemeStorage,
  upsertCustomTheme,
} from "../theme/theme.js"
import {
  buildSelector,
  cssValueToHex,
  describeElement,
  EDITABLE_PROPERTIES,
  isColorProperty,
  propertyToVariable,
  readComputedStyleValue,
} from "../theme/element_inspector.js"

export default class extends Controller {
  static targets = [
    "samplePanel",
    "highlight",
    "inspector",
    "selectorLabel",
    "propertyFields",
    "themeName",
    "baseTheme",
    "tokenList",
    "customThemeList",
    "designToggle",
    "status",
    "importFile",
  ]

  static values = {
    editingThemeId: String,
    sample: { type: String, default: "show" },
    designMode: { type: Boolean, default: false },
  }

  connect() {
    this.editingTheme =
      this.editingThemeIdValue ? findCustomTheme(this.editingThemeIdValue) : null
    this.draft =
      this.editingTheme ??
      createCustomTheme({
        label: "新しいテーマ",
        baseTheme: getStoredThemeId(),
      })

    if (this.hasThemeNameTarget) {
      this.themeNameTarget.value = this.draft.label
    }
    if (this.hasBaseThemeTarget) {
      this.baseThemeTarget.value = this.draft.baseTheme
    }

    this.samplePanelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.sampleName !== this.sampleValue
    })

    this.renderTokenList()
    this.renderCustomThemeList()
    this.applyDraftPreview()
  }

  disconnect() {
    applyTheme(getStoredThemeId())
  }

  applyDraftPreview() {
    upsertCustomTheme(this.draft)
    applyThemePreview(this.draft.id)
  }

  selectSample(event) {
    const button = event.currentTarget
    if (!(button instanceof HTMLButtonElement)) return

    this.sampleValue = button.dataset.sampleName ?? "show"
    this.samplePanelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.sampleName !== this.sampleValue
    })

    this.samplePanelTargets
      .filter((panel) => panel.dataset.sampleName === this.sampleValue)
      .forEach((panel) => {
        panel.querySelectorAll(".theme-studio-tab").forEach((tab) => {
          tab.classList.toggle("is-active", tab === button)
        })
      })

    event.currentTarget
      .closest(".theme-studio-preview-toolbar")
      ?.querySelectorAll(".theme-studio-tab")
      .forEach((tab) => {
        tab.classList.toggle("is-active", tab.dataset.sampleName === this.sampleValue)
      })

    this.clearSelection()
  }

  toggleDesignMode() {
    this.designModeValue = !this.designModeValue
    this.element.classList.toggle("theme-studio-design-mode", this.designModeValue)

    if (this.hasDesignToggleTarget) {
      this.designToggleTarget.textContent = this.designModeValue
        ? "Design モード: ON"
        : "Design モード: OFF"
      this.designToggleTarget.setAttribute("aria-pressed", String(this.designModeValue))
    }

    if (!this.designModeValue) {
      this.clearSelection()
    }
  }

  sampleClick(event) {
    if (!this.designModeValue) return

    event.preventDefault()
    event.stopPropagation()

    const sampleRoot = event.currentTarget
    if (!(sampleRoot instanceof HTMLElement)) return

    const element = event.target
    if (!(element instanceof HTMLElement) || element === sampleRoot) return

    this.selectElement(sampleRoot, element)
  }

  sampleMouseOver(event) {
    if (!this.designModeValue || this.selectedElement) return

    const sampleRoot = event.currentTarget
    const element = event.target
    if (!(sampleRoot instanceof HTMLElement) || !(element instanceof HTMLElement)) return
    if (element === sampleRoot) return

    this.positionHighlight(element)
  }

  sampleMouseOut(event) {
    if (!this.designModeValue || this.selectedElement) return
    if (this.hasHighlightTarget) this.highlightTarget.hidden = true
  }

  /** @param {HTMLElement} sampleRoot @param {HTMLElement} element */
  selectElement(sampleRoot, element) {
    this.selectedElement = element
    this.selectedSelector = buildSelector(sampleRoot, element)

    if (this.hasSelectorLabelTarget) {
      this.selectorLabelTarget.textContent = describeElement(element)
    }

    this.positionHighlight(element)
    this.renderPropertyFields(element)
  }

  /** @param {HTMLElement} element */
  positionHighlight(element) {
    if (!this.hasHighlightTarget) return

    const previewBody = this.highlightTarget.closest(".theme-studio-preview-body")
    if (!(previewBody instanceof HTMLElement)) return

    const elementRect = element.getBoundingClientRect()
    const bodyRect = previewBody.getBoundingClientRect()

    this.highlightTarget.hidden = false
    this.highlightTarget.style.top = `${elementRect.top - bodyRect.top + previewBody.scrollTop}px`
    this.highlightTarget.style.left = `${elementRect.left - bodyRect.left + previewBody.scrollLeft}px`
    this.highlightTarget.style.width = `${elementRect.width}px`
    this.highlightTarget.style.height = `${elementRect.height}px`
  }

  /** @param {HTMLElement} element */
  renderPropertyFields(element) {
    if (!this.hasPropertyFieldsTarget) return

    this.propertyFieldsTarget.replaceChildren()

    for (const { key, label } of EDITABLE_PROPERTIES) {
      const value = readComputedStyleValue(element, key)
      const row = document.createElement("div")
      row.className = "theme-studio-inspector-grid"

      const labelEl = document.createElement("label")
      labelEl.textContent = label
      labelEl.className = "text-sm kb-text-secondary"

      const inputWrap = document.createElement("div")
      inputWrap.className = "flex items-center gap-2"

      if (isColorProperty(key, value)) {
        const colorInput = document.createElement("input")
        colorInput.type = "color"
        colorInput.value = cssValueToHex(value)
        colorInput.dataset.property = key
        colorInput.addEventListener("input", () => {
          this.updateProperty(key, colorInput.value, element)
        })

        const textInput = document.createElement("input")
        textInput.type = "text"
        textInput.value = value
        textInput.className = "flex-1 font-mono text-xs kb-input rounded px-2 py-1"
        textInput.dataset.property = key
        textInput.addEventListener("change", () => {
          this.updateProperty(key, textInput.value, element)
        })

        colorInput.addEventListener("input", () => {
          textInput.value = colorInput.value
        })

        inputWrap.append(colorInput, textInput)
      } else {
        const textInput = document.createElement("input")
        textInput.type = "text"
        textInput.value = value
        textInput.className = "w-full font-mono text-xs kb-input rounded px-2 py-1"
        textInput.dataset.property = key
        textInput.addEventListener("change", () => {
          this.updateProperty(key, textInput.value, element)
        })
        inputWrap.append(textInput)
      }

      row.append(labelEl, inputWrap)
      this.propertyFieldsTarget.append(row)
    }
  }

  /** @param {string} property @param {string} value @param {HTMLElement} element */
  updateProperty(property, value, element) {
    const slot = element.dataset.themeSlot
    const variable = slot ? propertyToVariable(slot, property) : null

    if (variable) {
      this.draft.variables[variable] = value
    } else {
      this.upsertRule(this.selectedSelector, property, value)
    }

    this.applyDraftPreview()
    if (this.selectedElement) {
      this.renderPropertyFields(this.selectedElement)
    }
    this.renderTokenList()
    this.setStatus("スタイルを更新しました")
  }

  /** @param {string} selector @param {string} property @param {string} value */
  upsertRule(selector, property, value) {
    let rule = this.draft.rules.find((entry) => entry.selector === selector)
    if (!rule) {
      rule = { selector, properties: {} }
      this.draft.rules.push(rule)
    }
    rule.properties[property] = value
  }

  baseThemeChanged() {
    if (!this.hasBaseThemeTarget) return
    this.draft.baseTheme = this.baseThemeTarget.value
    this.draft.variables = {
      ...getThemeTokenDefaults(this.draft.baseTheme),
      ...this.draft.variables,
    }
    this.applyDraftPreview()
    this.renderTokenList()
  }

  themeNameChanged() {
    if (!this.hasThemeNameTarget) return
    this.draft.label = this.themeNameTarget.value.trim() || "新しいテーマ"
    this.setStatus("テーマ名を更新しました")
  }

  renderTokenList() {
    if (!this.hasTokenListTarget) return

    const tokens = Object.entries(this.draft.variables).sort(([a], [b]) => a.localeCompare(b))
    this.tokenListTarget.replaceChildren(
      ...tokens.map(([name, value]) => {
        const row = document.createElement("div")
        row.className = "theme-studio-token-row grid grid-cols-[minmax(0,1fr)_auto] gap-2 items-center"

        const label = document.createElement("span")
        label.className = "font-mono text-xs kb-text-secondary truncate"
        label.textContent = name
        label.title = name

        const input = document.createElement("input")
        input.type = "text"
        input.value = value
        input.addEventListener("change", () => {
          this.draft.variables[name] = input.value
          this.applyDraftPreview()
        })

        if (/^#|^rgb/.test(value)) {
          const color = document.createElement("input")
          color.type = "color"
          color.value = cssValueToHex(value)
          color.addEventListener("input", () => {
            input.value = color.value
            this.draft.variables[name] = color.value
            this.applyDraftPreview()
          })

          const wrap = document.createElement("div")
          wrap.className = "flex items-center gap-2"
          wrap.append(color, input)
          row.append(label, wrap)
        } else {
          row.append(label, input)
        }

        return row
      })
    )
  }

  renderCustomThemeList() {
    if (!this.hasCustomThemeListTarget) return

    const { customThemes } = loadThemeStorage()
    this.customThemeListTarget.replaceChildren(
      ...customThemes.map((theme) => {
        const item = document.createElement("li")
        item.className = "flex items-center justify-between gap-2 text-sm"

        const link = document.createElement("a")
        link.href = `/themes/studio?theme=${encodeURIComponent(theme.id)}`
        link.textContent = theme.label
        link.className = "kb-chrome-link hover:underline truncate"

        const del = document.createElement("button")
        del.type = "button"
        del.textContent = "削除"
        del.className = "shrink-0 text-xs text-red-600 hover:text-red-800"
        del.dataset.themeId = theme.id
        del.addEventListener("click", () => this.deleteTheme(theme.id))

        item.append(link, del)
        return item
      })
    )
  }

  /** @param {string} themeId */
  deleteTheme(themeId) {
    if (!window.confirm("このカスタムテーマを削除しますか？")) return
    deleteCustomTheme(themeId)
    if (this.draft.id === themeId) {
      this.draft = createCustomTheme({ label: "新しいテーマ", baseTheme: "default" })
    }
    this.renderCustomThemeList()
    applyTheme(getStoredThemeId())
    this.setStatus("テーマを削除しました")
  }

  saveTheme() {
    if (this.hasThemeNameTarget) {
      this.draft.label = this.themeNameTarget.value.trim() || this.draft.label
    }
    upsertCustomTheme(this.draft)
    this.renderCustomThemeList()
    this.setStatus("テーマを保存しました")
  }

  applyTheme() {
    this.saveTheme()
    applyTheme(this.draft.id)
    this.setStatus("テーマを適用しました")
  }

  newTheme() {
    this.draft = createCustomTheme({ label: "新しいテーマ", baseTheme: this.draft.baseTheme })
    if (this.hasThemeNameTarget) this.themeNameTarget.value = this.draft.label
    if (this.hasBaseThemeTarget) this.baseThemeTarget.value = this.draft.baseTheme
    this.applyDraftPreview()
    this.renderTokenList()
    this.clearSelection()
    this.setStatus("新規テーマを開始しました")
  }

  exportTheme() {
    const payload = {
      version: 1,
      exportedAt: new Date().toISOString(),
      theme: this.draft,
    }
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" })
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement("a")
    anchor.href = url
    anchor.download = `${this.draft.label.replace(/\s+/g, "-") || "kbmemo-theme"}.json`
    anchor.click()
    URL.revokeObjectURL(url)
    this.setStatus("テーマをエクスポートしました")
  }

  importTheme(event) {
    const input = event.target
    if (!(input instanceof HTMLInputElement) || !input.files?.[0]) return

    const file = input.files[0]
    const reader = new FileReader()
    reader.onload = () => {
      try {
        const parsed = JSON.parse(String(reader.result))
        const theme = parsed.theme ?? parsed
        this.draft = createCustomTheme({
          id: theme.id,
          label: theme.label ?? "インポートしたテーマ",
          baseTheme: theme.baseTheme ?? "default",
          variables: theme.variables ?? {},
          rules: theme.rules ?? [],
        })
        if (this.hasThemeNameTarget) this.themeNameTarget.value = this.draft.label
        if (this.hasBaseThemeTarget) this.baseThemeTarget.value = this.draft.baseTheme
        this.applyDraftPreview()
        this.renderTokenList()
        this.clearSelection()
        this.setStatus("テーマをインポートしました")
      } catch {
        this.setStatus("インポートに失敗しました（JSON 形式を確認してください）")
      } finally {
        input.value = ""
      }
    }
    reader.readAsText(file)
  }

  triggerImport() {
    this.importFileTarget.click()
  }

  clearSelection() {
    this.selectedElement = null
    this.selectedSelector = null
    if (this.hasHighlightTarget) this.highlightTarget.hidden = true
    if (this.hasSelectorLabelTarget) {
      this.selectorLabelTarget.textContent = "要素をクリックして選択"
    }
    if (this.hasPropertyFieldsTarget) this.propertyFieldsTarget.replaceChildren()
  }

  /** @param {string} message */
  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
