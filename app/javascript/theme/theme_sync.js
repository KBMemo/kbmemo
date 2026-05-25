import { THEME_CHANGE_EVENT } from "./theme.js"
import { loadThemeStorage, saveThemeStorage } from "./theme_storage.js"

const SYNC_DEBOUNCE_MS = 500

/** @returns {boolean} */
function themeSyncEnabled() {
  return document.querySelector('meta[name="kbmemo-theme-sync"]')?.getAttribute("content") === "true"
}

/** @returns {string} */
function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") ?? ""
}

/** @param {import("./theme_storage.js").ThemeStorageState} state */
function toServerPayload(state) {
  return {
    active_theme_id: state.activeThemeId,
    custom_themes: state.customThemes.map((theme) => ({
      id: theme.id,
      label: theme.label,
      base_theme: theme.baseTheme,
      variables: theme.variables,
      rules: theme.rules,
    })),
  }
}

/** @param {Record<string, unknown>} payload */
function fromServerPayload(payload) {
  return {
    activeThemeId:
      typeof payload.active_theme_id === "string"
        ? payload.active_theme_id
        : typeof payload.activeThemeId === "string"
          ? payload.activeThemeId
          : "default",
    customThemes: Array.isArray(payload.custom_themes || payload.customThemes)
      ? (payload.custom_themes || payload.customThemes).map((theme) => ({
          id: theme.id,
          label: theme.label,
          baseTheme: theme.base_theme ?? theme.baseTheme ?? "default",
          variables: theme.variables ?? {},
          rules: theme.rules ?? [],
        }))
      : [],
  }
}

let syncTimer = null

export function scheduleThemeSync() {
  if (!themeSyncEnabled()) return

  if (syncTimer != null) clearTimeout(syncTimer)
  syncTimer = setTimeout(async () => {
    syncTimer = null
    try {
      await fetch("/theme.json", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": csrfToken(),
        },
        body: JSON.stringify(toServerPayload(loadThemeStorage())),
        credentials: "same-origin",
      })
    } catch {
      // オフライン等 — localStorage のみで継続
    }
  }, SYNC_DEBOUNCE_MS)
}

/** @returns {Promise<boolean>} */
export async function pullThemeFromServer() {
  if (!themeSyncEnabled()) return false

  try {
    const response = await fetch("/theme.json", {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
    })
    if (!response.ok) return false

    const payload = await response.json()
    saveThemeStorage(fromServerPayload(payload))
    return true
  } catch {
    return false
  }
}

export function initThemeSync() {
  if (!themeSyncEnabled()) return

  document.addEventListener(THEME_CHANGE_EVENT, scheduleThemeSync)
}

/** @param {Record<string, unknown>} accountTheme */
export function bootstrapAccountTheme(accountTheme) {
  if (!accountTheme || typeof accountTheme !== "object") return

  saveThemeStorage(fromServerPayload(accountTheme))
}
