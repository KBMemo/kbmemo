/** AsciiDoc の 1 編集単位に相当する Asciidoctor 出力要素 */
import { hasUnitAdocSource, transferUnitAdocSource } from './wysiwyg_unit_source.js'
const UNIT_CLASS_NAMES = new Set([
  'paragraph',
  'listingblock',
  'literalblock',
  'imageblock',
  'admonitionblock',
  'quoteblock',
  'stemblock',
  'ulist',
  'olist',
  'tableblock',
  'exampleblock',
  'sidebarblock',
  'dlist',
  'colist',
  'hdlist',
])

/**
 * @param {HTMLElement} el
 */
export function isEditUnitElement(el) {
  const tag = el.tagName.toLowerCase()
  if (/^h[1-6]$/.test(tag)) return true
  return [...el.classList].some((name) => UNIT_CLASS_NAMES.has(name))
}

/**
 * @param {HTMLElement} el
 */
export function isStructuralContainer(el) {
  if (el.id === 'preamble') return true
  if (el.classList.contains('sectionbody')) return true
  return [...el.classList].some((name) => /^sect[0-5]$/.test(name))
}

/**
 * Flatten Asciidoctor HTML into one wrapper per edit unit (heading, paragraph, list, …).
 *
 * @param {HTMLElement} editorEl
 */
export function flattenAndWrapUnits(editorEl) {
  /** @type {{ element: HTMLElement, sourceUnit: HTMLElement | null }[]} */
  const units = []
  collectEditUnits(editorEl, units)

  editorEl.replaceChildren()
  for (const { element, sourceUnit } of units) {
    const wrapper = document.createElement('div')
    wrapper.className = 'wysiwyg-unit'
    wrapper.contentEditable = 'false'
    if (sourceUnit instanceof HTMLElement) {
      transferUnitAdocSource(sourceUnit, wrapper)
    }
    wrapper.append(element)
    editorEl.append(wrapper)
  }
}

/**
 * @param {ParentNode} container
 * @param {{ element: HTMLElement, sourceUnit: HTMLElement | null }[]} out
 */
function collectEditUnits(container, out) {
  for (const child of [...container.childNodes]) {
    if (child.nodeType === Node.TEXT_NODE) {
      const text = child.textContent?.trim()
      if (!text) continue
      const paragraph = document.createElement('div')
      paragraph.className = 'paragraph'
      const p = document.createElement('p')
      p.textContent = text
      paragraph.append(p)
      out.push({ element: paragraph, sourceUnit: null })
      continue
    }

    if (child.nodeType !== Node.ELEMENT_NODE) continue
    const el = /** @type {HTMLElement} */ (child)

    if (el.classList.contains('wysiwyg-unit')) {
      const sourceUnit = hasUnitAdocSource(el) ? el : null
      for (const inner of el.childNodes) {
        if (inner.nodeType === Node.ELEMENT_NODE && inner.classList.contains('wysiwyg-source-editor')) {
          continue
        }
        if (inner.nodeType === Node.ELEMENT_NODE) {
          out.push({ element: /** @type {HTMLElement} */ (inner), sourceUnit })
        }
      }
      continue
    }

    if (isStructuralContainer(el)) {
      collectEditUnits(el, out)
      continue
    }

    if (isEditUnitElement(el)) {
      out.push({ element: el, sourceUnit: null })
      continue
    }

    collectEditUnits(el, out)
  }
}
