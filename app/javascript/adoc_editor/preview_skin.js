/** @typedef {{ id: string, label: string, href: string | null }} PreviewSkin */

/** @type {PreviewSkin[]} */
export const PREVIEW_SKINS = [
  { id: "default", label: "Default", href: null },
  { id: "dark", label: "Dark", href: "/css/skins/dark.css" },
  { id: "sepia", label: "Sepia", href: "/css/skins/sepia.css" },
  { id: "minimal", label: "Minimal", href: "/css/skins/minimal.css" }
]

export const PREVIEW_SKIN_CHANGE_EVENT = "kbmemo:preview-skin-change"
export const PREVIEW_SKIN_SELECT_SELECTOR = "[data-preview-skin-select]"

const STORAGE_KEY = "kbmemo_adoc_preview_skin"
const STYLESHEET_ID = "kbmemo-adoc-preview-skin"
const SKIN_TARGET_SELECTOR = ".memo-body.asciidoctor, article.memo-body"

/**
 * @param {string} skinId
 * @returns {PreviewSkin}
 */
export function getSkin(skinId) {
  return PREVIEW_SKINS.find((skin) => skin.id === skinId) ?? PREVIEW_SKINS[0]
}

export function getStoredSkinId() {
  const stored = localStorage.getItem(STORAGE_KEY)
  return getSkin(stored ?? "").id
}

function collectSkinTargets() {
  return Array.from(document.querySelectorAll(SKIN_TARGET_SELECTOR))
}

/**
 * @param {HTMLSelectElement} selectEl
 */
export function populatePreviewSkinSelect(selectEl) {
  selectEl.replaceChildren(
    ...PREVIEW_SKINS.map((skin) => {
      const option = document.createElement("option")
      option.value = skin.id
      option.textContent = skin.label
      return option
    })
  )
}

/**
 * @param {string} skinId
 */
export function syncPreviewSkinSelects(skinId) {
  for (const select of document.querySelectorAll(PREVIEW_SKIN_SELECT_SELECTOR)) {
    if (select instanceof HTMLSelectElement && select.value !== skinId) {
      select.value = skinId
    }
  }
}

/**
 * @param {HTMLElement | HTMLElement[] | null | undefined} elements
 * @param {string} skinId
 */
export function applyPreviewSkin(elements, skinId) {
  const skin = getSkin(skinId)
  const targets =
    elements == null
      ? collectSkinTargets()
      : Array.isArray(elements)
        ? elements
        : [elements]

  for (const previewEl of targets) {
    for (const { id } of PREVIEW_SKINS) {
      previewEl.classList.remove(`preview-skin-${id}`)
    }
    previewEl.classList.add(`preview-skin-${skin.id}`)
  }

  let link = document.getElementById(STYLESHEET_ID)
  if (skin.href) {
    if (!link) {
      link = document.createElement("link")
      link.id = STYLESHEET_ID
      link.rel = "stylesheet"
      document.head.appendChild(link)
    }
    link.href = skin.href
  } else if (link) {
    link.remove()
  }

  localStorage.setItem(STORAGE_KEY, skin.id)
  syncPreviewSkinSelects(skin.id)
  document.dispatchEvent(
    new CustomEvent(PREVIEW_SKIN_CHANGE_EVENT, { detail: { skinId: skin.id } })
  )
  return skin.id
}

export function applyStoredPreviewSkin() {
  return applyPreviewSkin(null, getStoredSkinId())
}

/**
 * @param {HTMLSelectElement} selectEl
 * @param {HTMLElement | null | undefined} [previewEl]
 */
export function initPreviewSkinSelect(selectEl, previewEl) {
  populatePreviewSkinSelect(selectEl)
  selectEl.dataset.previewSkinSelect = "true"

  const activeSkinId = applyPreviewSkin(null, getStoredSkinId())
  selectEl.value = activeSkinId

  selectEl.addEventListener("change", () => {
    applyPreviewSkin(null, selectEl.value)
  })
}
