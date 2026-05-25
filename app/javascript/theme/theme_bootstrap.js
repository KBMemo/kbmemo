import { pullThemeFromServer, initThemeSync } from "./theme_sync.js"
import { applyTheme, getStoredThemeId } from "./theme.js"

let themeBootstrapPromise = null

export function ensureThemeBootstrapped() {
  if (!themeBootstrapPromise) {
    themeBootstrapPromise = (async () => {
      await pullThemeFromServer()
      applyTheme(getStoredThemeId())
    })()
  }
  return themeBootstrapPromise
}

export async function applyStoredThemeWithSync() {
  await ensureThemeBootstrapped()
  return applyTheme(getStoredThemeId())
}

export { initThemeSync, scheduleThemeSync, bootstrapAccountTheme } from "./theme_sync.js"
