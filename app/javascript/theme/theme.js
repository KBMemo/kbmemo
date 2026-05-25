import { BUILTIN_THEMES, getBuiltinTheme } from "./builtin_themes.js"
import {
  findCustomTheme,
  loadThemeStorage,
  saveThemeStorage,
} from "./theme_storage.js"

export const THEME_CHANGE_EVENT = "kbmemo:theme-change"
export const THEME_SELECT_SELECTOR = "[data-theme-select]"

const CUSTOM_STYLE_ID = "kbmemo-custom-theme-style"

/** @typedef {import("./theme_storage.js").CustomTheme} CustomTheme */

/** @returns {Array<{ id: string, label: string, builtin: boolean }>} */
export function listAvailableThemes() {
  const { customThemes } = loadThemeStorage()
  return [
    ...BUILTIN_THEMES.map((theme) => ({ ...theme, builtin: true })),
    ...customThemes.map((theme) => ({ id: theme.id, label: theme.label, builtin: false })),
  ]
}

export function getStoredThemeId() {
  const { activeThemeId } = loadThemeStorage()
  if (findCustomTheme(activeThemeId)) return activeThemeId
  if (BUILTIN_THEMES.some((theme) => theme.id === activeThemeId)) return activeThemeId
  return "default"
}

/** @param {string} themeId */
export function resolveTheme(themeId) {
  const custom = findCustomTheme(themeId)
  if (custom) return custom

  const builtin = getBuiltinTheme(themeId)
  return { ...builtin, baseTheme: builtin.id, variables: {}, rules: [] }
}

/** @param {string} themeId */
function renderCustomThemeCss(themeId) {
  const custom = findCustomTheme(themeId)
  if (!custom) return ""

  const variableLines = Object.entries(custom.variables)
    .map(([name, value]) => `  ${name}: ${value};`)
    .join("\n")

  const ruleBlocks = custom.rules
    .map((rule) => {
      const props = Object.entries(rule.properties)
        .map(([name, value]) => `  ${name}: ${value};`)
        .join("\n")
      return `${rootSelector} ${rule.selector} {\n${props}\n}`
    })
    .join("\n\n")

  const rootSelector = `html[data-kb-theme="${custom.id}"]`
  const variableBlock = variableLines ? `${rootSelector} {\n${variableLines}\n}` : ""

  return [variableBlock, ruleBlocks].filter(Boolean).join("\n\n")
}

/** @param {string | null} themeId */
function syncCustomThemeStyle(themeId) {
  let styleEl = document.getElementById(CUSTOM_STYLE_ID)
  const css = themeId ? renderCustomThemeCss(themeId) : ""

  if (!css) {
    styleEl?.remove()
    return
  }

  if (!styleEl) {
    styleEl = document.createElement("style")
    styleEl.id = CUSTOM_STYLE_ID
    document.head.appendChild(styleEl)
  }

  styleEl.textContent = css
}

/**
 * @param {HTMLSelectElement} selectEl
 */
export function populateThemeSelect(selectEl) {
  selectEl.replaceChildren(
    ...listAvailableThemes().map((theme) => {
      const option = document.createElement("option")
      option.value = theme.id
      option.textContent = theme.builtin ? theme.label : `${theme.label} (custom)`
      return option
    })
  )
}

/** @param {string} themeId */
export function syncThemeSelects(themeId) {
  for (const select of document.querySelectorAll(THEME_SELECT_SELECTOR)) {
    if (select instanceof HTMLSelectElement && select.value !== themeId) {
      select.value = themeId
    }
  }
}

/** @param {string} themeId */
export function applyTheme(themeId) {
  const theme = resolveTheme(themeId)
  const root = document.documentElement
  const custom = findCustomTheme(themeId)
  const baseThemeId = custom?.baseTheme ?? getBuiltinTheme(themeId).id

  root.dataset.kbTheme = themeId
  root.dataset.kbThemeBase = baseThemeId

  if (custom) {
    syncCustomThemeStyle(themeId)
  } else {
    syncCustomThemeStyle(null)
  }

  const state = loadThemeStorage()
  state.activeThemeId = theme.id
  saveThemeStorage(state)

  syncThemeSelects(theme.id)
  document.dispatchEvent(
    new CustomEvent(THEME_CHANGE_EVENT, { detail: { themeId: theme.id } })
  )

  return theme.id
}

export function applyStoredTheme() {
  return applyTheme(getStoredThemeId())
}

/**
 * @param {HTMLSelectElement} selectEl
 */
export function initThemeSelect(selectEl) {
  populateThemeSelect(selectEl)
  selectEl.dataset.themeSelect = "true"

  const activeThemeId = applyStoredTheme()
  selectEl.value = activeThemeId

  selectEl.addEventListener("change", () => {
    applyTheme(selectEl.value)
  })
}

/** Studio preview applies theme without persisting active selection. */
export function applyThemePreview(themeId) {
  const custom = findCustomTheme(themeId)
  const baseThemeId = custom?.baseTheme ?? getBuiltinTheme(themeId).id
  const root = document.documentElement

  root.dataset.kbTheme = themeId
  root.dataset.kbThemeBase = baseThemeId

  if (custom) {
    syncCustomThemeStyle(themeId)
  } else {
    syncCustomThemeStyle(null)
  }
}

export {
  createCustomTheme,
  deleteCustomTheme,
  findCustomTheme,
  loadThemeStorage,
  saveThemeStorage,
  upsertCustomTheme,
} from "./theme_storage.js"

export { BUILTIN_THEMES, getThemeTokenDefaults, THEME_TOKEN_DEFAULTS } from "./builtin_themes.js"
