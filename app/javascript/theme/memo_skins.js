import {
  DEFAULT_SKIN_ID,
  findCustomSkin,
  loadThemeStorage,
  saveThemeStorage,
} from "./theme_storage.js"

export const SKIN_CHANGE_EVENT = "kbmemo:skin-change"
export const SKIN_SELECT_SELECTOR = "[data-skin-select]"

const CUSTOM_SKIN_STYLE_ID = "kbmemo-custom-skin-style"

/** @typedef {import("./theme_storage.js").CustomSkin} CustomSkin */

/** @typedef {{ id: string, label: string, builtin: true }} BuiltinSkin */

/**
 * 本文スキン（chrome テーマと独立に `.memo-body` 系へ適用）。
 * `auto` は従来どおり chrome テーマの `--mg-*` に追従する（既存挙動）。
 * @type {BuiltinSkin[]}
 */
export const BUILTIN_SKINS = [
  { id: "auto", label: "Auto（テーマ追従）", builtin: true },
  { id: "github", label: "GitHub", builtin: true },
]

/** @param {string} skinId */
export function getBuiltinSkin(skinId) {
  return BUILTIN_SKINS.find((skin) => skin.id === skinId) ?? BUILTIN_SKINS[0]
}

/** @returns {Array<{ id: string, label: string, builtin: boolean }>} */
export function listAvailableSkins() {
  const { customSkins } = loadThemeStorage()
  return [
    ...BUILTIN_SKINS.map((skin) => ({ ...skin, builtin: true })),
    ...customSkins.map((skin) => ({ id: skin.id, label: skin.label, builtin: false })),
  ]
}

export function getStoredSkinId() {
  const { activeSkinId } = loadThemeStorage()
  if (findCustomSkin(activeSkinId)) return activeSkinId
  if (BUILTIN_SKINS.some((skin) => skin.id === activeSkinId)) return activeSkinId
  return DEFAULT_SKIN_ID
}

/** @param {string} skinId */
function renderCustomSkinCss(skinId) {
  const custom = findCustomSkin(skinId)
  if (!custom || !custom.css) return ""
  // ユーザー CSS はそのまま注入する。`.memo-body` 系へのスコープ／サニタイズは Phase 3 で本格化する。
  return custom.css
}

/** @param {string | null} skinId */
function syncCustomSkinStyle(skinId) {
  let styleEl = document.getElementById(CUSTOM_SKIN_STYLE_ID)
  const css = skinId ? renderCustomSkinCss(skinId) : ""

  if (!css) {
    styleEl?.remove()
    return
  }

  if (!styleEl) {
    styleEl = document.createElement("style")
    styleEl.id = CUSTOM_SKIN_STYLE_ID
    document.head.appendChild(styleEl)
  }

  styleEl.textContent = css
}

/** @param {HTMLSelectElement} selectEl */
export function populateSkinSelect(selectEl) {
  selectEl.replaceChildren(
    ...listAvailableSkins().map((skin) => {
      const option = document.createElement("option")
      option.value = skin.id
      option.textContent = skin.builtin ? skin.label : `${skin.label} (custom)`
      return option
    })
  )
}

/** @param {string} skinId */
export function syncSkinSelects(skinId) {
  for (const select of document.querySelectorAll(SKIN_SELECT_SELECTOR)) {
    if (select instanceof HTMLSelectElement && select.value !== skinId) {
      select.value = skinId
    }
  }
}

/** @param {string} skinId */
export function applySkin(skinId) {
  const custom = findCustomSkin(skinId)
  const resolvedId = custom
    ? custom.id
    : BUILTIN_SKINS.some((skin) => skin.id === skinId)
      ? skinId
      : DEFAULT_SKIN_ID

  document.documentElement.dataset.kbSkin = resolvedId
  syncCustomSkinStyle(custom ? resolvedId : null)

  const state = loadThemeStorage()
  state.activeSkinId = resolvedId
  saveThemeStorage(state)

  syncSkinSelects(resolvedId)
  document.dispatchEvent(new CustomEvent(SKIN_CHANGE_EVENT, { detail: { skinId: resolvedId } }))

  return resolvedId
}

export function applyStoredSkin() {
  return applySkin(getStoredSkinId())
}

/** @param {HTMLSelectElement} selectEl */
export function initSkinSelect(selectEl) {
  populateSkinSelect(selectEl)
  selectEl.dataset.skinSelect = "true"

  const activeSkinId = applyStoredSkin()
  selectEl.value = activeSkinId

  selectEl.addEventListener("change", () => {
    applySkin(selectEl.value)
  })
}

export {
  createCustomSkin,
  deleteCustomSkin,
  findCustomSkin,
  upsertCustomSkin,
} from "./theme_storage.js"
