import { propertyToVariable, slotLabel, THEME_SLOTS } from "./theme_slots.js"

/** @param {Element} element */
export function describeElement(element) {
  if (!(element instanceof HTMLElement)) return element.tagName.toLowerCase()

  if (element.dataset.themeSlot) {
    const label = slotLabel(element.dataset.themeSlot)
    return `${label} (${element.dataset.themeSlot})`
  }

  return buildDomPath(element)
}

/** @param {Element} root @param {Element} element */
export function buildSelector(root, element) {
  if (!(element instanceof HTMLElement)) return element.tagName.toLowerCase()

  if (element.dataset.themeSlot) {
    return `[data-theme-slot="${element.dataset.themeSlot}"]`
  }

  const path = []
  let current = element

  while (current && current !== root && current instanceof HTMLElement) {
    if (current.dataset.themeSlot) {
      path.unshift(`[data-theme-slot="${current.dataset.themeSlot}"]`)
      break
    }

    let segment = current.tagName.toLowerCase()
    if (current.id) {
      segment += `#${CSS.escape(current.id)}`
      path.unshift(segment)
      break
    }

    if (current.classList.length > 0) {
      const classes = Array.from(current.classList)
        .slice(0, 2)
        .map((name) => `.${CSS.escape(name)}`)
        .join("")
      segment += classes
    }

    const parent = current.parentElement
    if (parent) {
      const siblings = Array.from(parent.children).filter(
        (child) => child.tagName === current.tagName
      )
      if (siblings.length > 1) {
        const index = siblings.indexOf(current) + 1
        segment += `:nth-of-type(${index})`
      }
    }

    path.unshift(segment)
    current = current.parentElement
  }

  return path.join(" > ")
}

/** @param {HTMLElement} element */
function buildDomPath(element) {
  const parts = []
  let current = element

  while (current && current !== document.body) {
    let part = current.tagName.toLowerCase()
    if (current.id) {
      part += `#${current.id}`
      parts.unshift(part)
      break
    }
    if (current.dataset.themeSlot) {
      part = `[data-theme-slot="${current.dataset.themeSlot}"]`
      parts.unshift(part)
      break
    }
    parts.unshift(part)
    current = current.parentElement
  }

  return parts.join(" > ")
}

/** @type {readonly { key: string, label: string }[]} */
export const EDITABLE_PROPERTIES = [
  { key: "color", label: "文字色" },
  { key: "background-color", label: "背景色" },
  { key: "border-color", label: "枠線色" },
  { key: "font-size", label: "文字サイズ" },
  { key: "font-weight", label: "太さ" },
  { key: "padding", label: "余白" },
  { key: "border-radius", label: "角丸" },
]

/** @param {HTMLElement} element @param {string} property */
export function readComputedStyleValue(element, property) {
  return getComputedStyle(element).getPropertyValue(property).trim()
}

/** @param {string} cssValue */
export function cssValueToHex(cssValue) {
  if (!cssValue) return "#000000"
  if (cssValue.startsWith("#")) return cssValue

  const canvas = document.createElement("canvas")
  canvas.width = canvas.height = 1
  const ctx = canvas.getContext("2d")
  if (!ctx) return "#000000"

  ctx.fillStyle = cssValue
  ctx.fillRect(0, 0, 1, 1)
  const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data
  return `#${[r, g, b].map((n) => n.toString(16).padStart(2, "0")).join("")}`
}

/** @param {string} property @param {string} value */
export function isColorProperty(property, value) {
  return (
    property.includes("color") ||
    property === "background-color" ||
    /^#|^rgb|^hsl/.test(value)
  )
}

export { propertyToVariable, slotLabel, THEME_SLOTS }
