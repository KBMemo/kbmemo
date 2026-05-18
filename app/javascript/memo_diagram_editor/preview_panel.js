const PREVIEW_MAX_HEIGHT = 480

function parseSvgLength(value) {
  if (!value) return null
  const n = parseFloat(String(value).trim())
  return Number.isFinite(n) && n > 0 ? n : null
}

function svgIntrinsicSize(svg) {
  const widthAttr = svg.getAttribute("width") ?? ""
  const heightAttr = svg.getAttribute("height") ?? ""
  let width = widthAttr && !widthAttr.includes("%") ? parseSvgLength(widthAttr) : null
  let height = heightAttr && !heightAttr.includes("%") ? parseSvgLength(heightAttr) : null

  if (width && height) return { width, height }

  const vb = svg.viewBox?.baseVal
  if (vb && vb.width > 0 && vb.height > 0) {
    return { width: vb.width, height: vb.height }
  }

  try {
    const box = svg.getBBox()
    if (box.width > 0 && box.height > 0) {
      return { width: box.width, height: box.height }
    }
  } catch {
    /* ignore */
  }

  return null
}

function sizePreviewObject(obj, container) {
  const apply = () => {
    try {
      const svg = obj.contentDocument?.documentElement
      if (!svg || svg.localName !== "svg") return

      const intrinsic = svgIntrinsicSize(svg)
      if (!intrinsic) return

      const maxWidth = Math.min(720, (container?.clientWidth ?? 640) * 0.98)
      let { width, height } = intrinsic
      if (width > maxWidth) {
        height = (height * maxWidth) / width
        width = maxWidth
      }
      if (height > PREVIEW_MAX_HEIGHT) {
        width = (width * PREVIEW_MAX_HEIGHT) / height
        height = PREVIEW_MAX_HEIGHT
      }

      obj.style.width = `${Math.round(width)}px`
      obj.style.height = `${Math.round(height)}px`
    } catch {
      /* same-origin blob URL 想定 */
    }
  }

  obj.addEventListener("load", apply)
  if (obj.contentDocument?.documentElement) apply()
}

/**
 * @param {HTMLElement} container
 * @param {string} svgText
 * @returns {() => void} revoke blob URL
 */
export function renderSvgInPreviewPanel(container, svgText) {
  container.replaceChildren()

  const obj = document.createElement("object")
  obj.type = "image/svg+xml"
  obj.className = "memo-diagram-editor-preview-object"
  obj.setAttribute("aria-label", "ダイアグラムプレビュー")

  const blob = new Blob([svgText], { type: "image/svg+xml;charset=utf-8" })
  const url = URL.createObjectURL(blob)
  obj.data = url
  sizePreviewObject(obj, container)
  container.appendChild(obj)

  return () => URL.revokeObjectURL(url)
}
