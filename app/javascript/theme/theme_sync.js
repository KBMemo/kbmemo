import { csrfFetchHeaders, getCsrfToken } from "@kbmemo/adoc-kbmemo"
import { THEME_CHANGE_EVENT } from "./theme.js"
import { SKIN_CHANGE_EVENT } from "./memo_skins.js"
import { DEFAULT_SKIN_ID, loadThemeStorage, saveThemeStorage } from "./theme_storage.js"

const SYNC_DEBOUNCE_MS = 500

/** @returns {boolean} */
function themeSyncEnabled() {
  return document.querySelector('meta[name="kbmemo-theme-sync"]')?.getAttribute("content") === "true"
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
    active_skin_id: state.activeSkinId ?? DEFAULT_SKIN_ID,
    custom_skins: (state.customSkins ?? []).map((skin) => ({
      id: skin.id,
      label: skin.label,
      css: skin.css ?? "",
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
    activeSkinId:
      typeof payload.active_skin_id === "string"
        ? payload.active_skin_id
        : typeof payload.activeSkinId === "string"
          ? payload.activeSkinId
          : DEFAULT_SKIN_ID,
    customSkins: Array.isArray(payload.custom_skins || payload.customSkins)
      ? (payload.custom_skins || payload.customSkins).map((skin) => ({
          id: skin.id,
          label: skin.label,
          css: skin.css ?? "",
        }))
      : [],
  }
}

let syncTimer = null
let syncChain = Promise.resolve()

async function patchThemePreference(attempt = 0) {
  const token = getCsrfToken()
  const payload = toServerPayload(loadThemeStorage())
  if (token) payload.authenticity_token = token

  const response = await fetch("/theme.json", {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      ...csrfFetchHeaders(),
    },
    body: JSON.stringify(payload),
    credentials: "same-origin",
  })

  if (response.status === 422 && attempt === 0) {
    await new Promise((resolve) => setTimeout(resolve, 50))
    return patchThemePreference(1)
  }

  return response
}

export function scheduleThemeSync() {
  if (!themeSyncEnabled()) return

  if (syncTimer != null) clearTimeout(syncTimer)
  syncTimer = setTimeout(() => {
    syncTimer = null
    syncChain = syncChain
      .catch(() => {})
      .then(async () => {
        try {
          await patchThemePreference()
        } catch {
          // オフライン等 — localStorage のみで継続
        }
      })
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
  document.addEventListener(SKIN_CHANGE_EVENT, scheduleThemeSync)
}

/** @param {Record<string, unknown>} accountTheme */
export function bootstrapAccountTheme(accountTheme) {
  if (!accountTheme || typeof accountTheme !== "object") return

  saveThemeStorage(fromServerPayload(accountTheme))
}
