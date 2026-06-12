const PREVIEW_MAX_HEIGHT = 480

function sizePreviewImage(img, container) {
  const apply = () => {
    if (!img.naturalWidth || !img.naturalHeight) return

    const maxWidth = Math.min(720, (container?.clientWidth ?? 640) * 0.98)
    let width = img.naturalWidth
    let height = img.naturalHeight
    if (width > maxWidth) {
      height = (height * maxWidth) / width
      width = maxWidth
    }
    if (height > PREVIEW_MAX_HEIGHT) {
      width = (width * PREVIEW_MAX_HEIGHT) / height
      height = PREVIEW_MAX_HEIGHT
    }

    img.style.width = `${Math.round(width)}px`
    img.style.height = `${Math.round(height)}px`
  }

  img.addEventListener("load", apply)
  if (img.complete) apply()
}

/**
 * @param {HTMLElement} container
 * @param {string} svgText
 * @returns {() => void} revoke blob URL
 */
export function renderSvgInPreviewPanel(container, svgText) {
  container.replaceChildren()

  const img = document.createElement("img")
  img.className = "memo-diagram-editor-preview-image"
  img.alt = "ダイアグラムプレビュー"
  img.decoding = "async"

  const blob = new Blob([svgText], { type: "image/svg+xml;charset=utf-8" })
  const url = URL.createObjectURL(blob)
  img.src = url
  sizePreviewImage(img, container)
  container.appendChild(img)

  return () => URL.revokeObjectURL(url)
}
