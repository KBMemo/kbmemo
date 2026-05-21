/** @typedef {{ id: string, label: string, href: string | null }} PreviewSkin */

/** @type {PreviewSkin[]} */
export const PREVIEW_SKINS = [
  { id: "default", label: "Default", href: null },
  { id: "dark", label: "Dark", href: "/css/skins/dark.css" },
  { id: "sepia", label: "Sepia", href: "/css/skins/sepia.css" },
  { id: "minimal", label: "Minimal", href: "/css/skins/minimal.css" }
]

const STORAGE_KEY = "kbmemo_adoc_preview_skin"
const STYLESHEET_ID = "kbmemo-adoc-preview-skin"

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

/**
 * @param {HTMLElement | HTMLElement[]} elements
 * @param {string} skinId
 */
export function applyPreviewSkin(elements, skinId) {
  const skin = getSkin(skinId)
  const targets = Array.isArray(elements) ? elements : [elements]

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
  return skin.id
}

/**
 * @param {HTMLSelectElement} selectEl
 * @param {HTMLElement} previewEl
 */
export function initPreviewSkinSelect(selectEl, previewEl) {
  selectEl.replaceChildren(
    ...PREVIEW_SKINS.map((skin) => {
      const option = document.createElement("option")
      option.value = skin.id
      option.textContent = skin.label
      return option
    })
  )

  const activeSkinId = applyPreviewSkin(previewEl, getStoredSkinId())
  selectEl.value = activeSkinId

  selectEl.addEventListener("change", () => {
    applyPreviewSkin(previewEl, selectEl.value)
  })
}
