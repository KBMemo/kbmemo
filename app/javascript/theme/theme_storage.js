import { getBuiltinTheme, THEME_TOKEN_DEFAULTS } from "./builtin_themes.js"

/** @typedef {{ selector: string, properties: Record<string, string> }} ThemeRule */

/**
 * @typedef {object} CustomTheme
 * @property {string} id
 * @property {string} label
 * @property {string} baseTheme
 * @property {Record<string, string>} variables
 * @property {ThemeRule[]} rules
 */

/**
 * @typedef {object} CustomSkin
 * @property {string} id
 * @property {string} label
 * @property {string} css
 */

/**
 * @typedef {object} ThemeStorageState
 * @property {string} activeThemeId
 * @property {CustomTheme[]} customThemes
 * @property {string} activeSkinId
 * @property {CustomSkin[]} customSkins
 */

export const THEME_STORAGE_KEY = "kbmemo_themes_v1"
export const DEFAULT_SKIN_ID = "auto"
const LEGACY_SKIN_STORAGE_KEY = "kbmemo_adoc_preview_skin"

/** @returns {ThemeStorageState} */
export function loadThemeStorage() {
  migrateLegacySkinStorage()

  try {
    const raw = localStorage.getItem(THEME_STORAGE_KEY)
    if (!raw) return defaultThemeStorage()
    const parsed = JSON.parse(raw)
    return normalizeThemeStorage(parsed)
  } catch {
    return defaultThemeStorage()
  }
}

/** @param {ThemeStorageState} state */
export function saveThemeStorage(state) {
  localStorage.setItem(THEME_STORAGE_KEY, JSON.stringify(normalizeThemeStorage(state)))
}

/** @returns {ThemeStorageState} */
function defaultThemeStorage() {
  return { activeThemeId: "default", customThemes: [], activeSkinId: DEFAULT_SKIN_ID, customSkins: [] }
}

/** @param {unknown} value */
function normalizeThemeStorage(value) {
  const fallback = defaultThemeStorage()
  if (!value || typeof value !== "object") return fallback

  const record = /** @type {Record<string, unknown>} */ (value)
  const activeThemeId =
    typeof record.activeThemeId === "string" ? record.activeThemeId : fallback.activeThemeId
  const customThemes = Array.isArray(record.customThemes)
    ? record.customThemes.map(normalizeCustomTheme).filter(Boolean)
    : []
  const activeSkinId =
    typeof record.activeSkinId === "string" ? record.activeSkinId : fallback.activeSkinId
  const customSkins = Array.isArray(record.customSkins)
    ? record.customSkins.map(normalizeCustomSkin).filter(Boolean)
    : []

  return { activeThemeId, customThemes, activeSkinId, customSkins }
}

/** @param {unknown} value */
function normalizeCustomSkin(value) {
  if (!value || typeof value !== "object") return null

  const record = /** @type {Record<string, unknown>} */ (value)
  const id = typeof record.id === "string" ? record.id : null
  const label = typeof record.label === "string" ? record.label : null
  const css = typeof record.css === "string" ? record.css : ""
  if (!id || !label) return null

  return /** @type {CustomSkin} */ ({ id, label, css })
}

/** @param {unknown} value */
function normalizeCustomTheme(value) {
  if (!value || typeof value !== "object") return null

  const record = /** @type {Record<string, unknown>} */ (value)
  const id = typeof record.id === "string" ? record.id : null
  const label = typeof record.label === "string" ? record.label : null
  const baseTheme =
    typeof record.baseTheme === "string" ? getBuiltinTheme(record.baseTheme).id : "default"
  if (!id || !label) return null

  const variables =
    record.variables && typeof record.variables === "object"
      ? Object.fromEntries(
          Object.entries(record.variables).filter(
            ([key, val]) => typeof key === "string" && typeof val === "string"
          )
        )
      : {}

  const rules = Array.isArray(record.rules)
    ? record.rules
        .map((rule) => {
          if (!rule || typeof rule !== "object") return null
          const ruleRecord = /** @type {Record<string, unknown>} */ (rule)
          const selector = typeof ruleRecord.selector === "string" ? ruleRecord.selector : null
          const properties =
            ruleRecord.properties && typeof ruleRecord.properties === "object"
              ? Object.fromEntries(
                  Object.entries(ruleRecord.properties).filter(
                    ([key, val]) => typeof key === "string" && typeof val === "string"
                  )
                )
              : {}
          if (!selector || Object.keys(properties).length === 0) return null
          return { selector, properties }
        })
        .filter(Boolean)
    : []

  return /** @type {CustomTheme} */ ({ id, label, baseTheme, variables, rules })
}

function migrateLegacySkinStorage() {
  if (localStorage.getItem(THEME_STORAGE_KEY)) return

  const legacySkin = localStorage.getItem(LEGACY_SKIN_STORAGE_KEY)
  if (!legacySkin) return

  const activeThemeId = getBuiltinTheme(legacySkin).id
  saveThemeStorage({ activeThemeId, customThemes: [] })
}

/** @param {Partial<CustomTheme> & { label: string, baseTheme?: string }} input */
export function createCustomTheme(input) {
  const baseTheme = getBuiltinTheme(input.baseTheme ?? "default").id
  const id = input.id ?? `custom-${crypto.randomUUID()}`
  return /** @type {CustomTheme} */ ({
    id,
    label: input.label.trim() || "Custom theme",
    baseTheme,
    variables: { ...THEME_TOKEN_DEFAULTS[baseTheme], ...(input.variables ?? {}) },
    rules: input.rules ?? [],
  })
}

/** @param {string} themeId */
export function findCustomTheme(themeId) {
  return loadThemeStorage().customThemes.find((theme) => theme.id === themeId) ?? null
}

/** @param {CustomTheme} theme */
export function upsertCustomTheme(theme) {
  const state = loadThemeStorage()
  const index = state.customThemes.findIndex((entry) => entry.id === theme.id)
  if (index >= 0) {
    state.customThemes[index] = theme
  } else {
    state.customThemes.push(theme)
  }
  saveThemeStorage(state)
  return theme
}

/** @param {string} themeId */
export function deleteCustomTheme(themeId) {
  const state = loadThemeStorage()
  state.customThemes = state.customThemes.filter((theme) => theme.id !== themeId)
  if (state.activeThemeId === themeId) {
    state.activeThemeId = "default"
  }
  saveThemeStorage(state)
}

/** @param {{ id?: string, label: string, css?: string }} input */
export function createCustomSkin(input) {
  const id = input.id ?? `custom-skin-${crypto.randomUUID()}`
  return /** @type {CustomSkin} */ ({
    id,
    label: input.label.trim() || "Custom skin",
    css: input.css ?? "",
  })
}

/** @param {string} skinId */
export function findCustomSkin(skinId) {
  return loadThemeStorage().customSkins.find((skin) => skin.id === skinId) ?? null
}

/** @param {CustomSkin} skin */
export function upsertCustomSkin(skin) {
  const state = loadThemeStorage()
  const index = state.customSkins.findIndex((entry) => entry.id === skin.id)
  if (index >= 0) {
    state.customSkins[index] = skin
  } else {
    state.customSkins.push(skin)
  }
  saveThemeStorage(state)
  return skin
}

/** @param {string} skinId */
export function deleteCustomSkin(skinId) {
  const state = loadThemeStorage()
  state.customSkins = state.customSkins.filter((skin) => skin.id !== skinId)
  if (state.activeSkinId === skinId) {
    state.activeSkinId = DEFAULT_SKIN_ID
  }
  saveThemeStorage(state)
}
