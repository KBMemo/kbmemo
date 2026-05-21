import { getAsciidoctor } from './instance.js'

/** @typedef {{ context: string, type?: string, text?: string, target?: string, attributes?: Record<string, unknown> }} CapturedInline */

/**
 * @param {import('@asciidoctor/core').AbstractNode} node
 * @param {string} text
 * @returns {CapturedInline[]}
 */
export function captureInlines(node, text) {
  const captured = []
  const Inline = getAsciidoctor().Inline
  const originalConvert = Inline.prototype.$convert

  Inline.prototype.$convert = function captureInlineConvert() {
    captured.push({
      context: this.getContext(),
      type: normalizeType(this.getType?.()),
      text: this.getText?.(),
      target: this.getTarget?.(),
      attributes: this.getAttributes?.(),
    })
    return originalConvert.call(this)
  }

  try {
    node.applySubstitutions(text)
  } finally {
    Inline.prototype.$convert = originalConvert
  }

  return captured
}

/**
 * @param {unknown} type
 */
function normalizeType(type) {
  if (typeof type === 'string') return type
  return undefined
}

/**
 * @param {CapturedInline} inline
 */
export function inlineClassName(inline) {
  if (inline.context === 'quoted') {
    switch (inline.type) {
      case 'strong':
        return 'adoc-strong'
      case 'emphasis':
        return 'adoc-emphasis'
      case 'monospaced':
      case 'passthrough':
        return 'adoc-monospace'
      default:
        return 'adoc-inline'
    }
  }

  if (inline.context === 'anchor') {
    switch (inline.type) {
      case 'link':
        return 'adoc-link'
      case 'xref':
        return 'adoc-macro'
      default:
        return 'adoc-link'
    }
  }

  if (inline.context === 'kbd') return 'adoc-kbd'
  if (inline.context === 'menu') return 'adoc-menu'
  if (inline.context === 'button') return 'adoc-button'

  return 'adoc-inline'
}

/**
 * @param {string} blockText
 * @param {CapturedInline} inline
 * @param {number} fromIndex
 */
export function findInlineMarkup(blockText, inline, fromIndex = 0) {
  const text = inline.text ?? ''
  const patterns = markupPatterns(inline, text)

  for (const pattern of patterns) {
    const index = blockText.indexOf(pattern, fromIndex)
    if (index >= 0) {
      return { from: index, to: index + pattern.length }
    }
  }

  return null
}

/**
 * @param {CapturedInline} inline
 * @param {string} text
 * @returns {string[]}
 */
function markupPatterns(inline, text) {
  if (inline.context === 'quoted') {
    return quotedPatterns(inline.type, text)
  }

  if (inline.context === 'anchor') {
    return anchorPatterns(inline, text)
  }

  if (inline.context === 'kbd') {
    return kbdPatterns(inline.attributes)
  }

  if (inline.context === 'menu') {
    return menuPatterns(inline.attributes)
  }

  if (inline.context === 'button') {
    const label = buttonLabel(inline.attributes)
    return label ? [`btn:[${label}]`] : []
  }

  return []
}

/**
 * @param {string | undefined} type
 * @param {string} text
 */
function quotedPatterns(type, text) {
  switch (type) {
    case 'strong':
      return [`**${text}**`, `*${text}*`]
    case 'emphasis':
      return [`__${text}__`, `_${text}_`]
    case 'monospaced':
      return [`\`${text}\``, `+${text}+`]
    case 'passthrough':
      return [`+${text}+`, `\`${text}\``]
    default:
      return [`*${text}*`, `_${text}_`, `\`${text}\``]
  }
}

/**
 * @param {CapturedInline} inline
 * @param {string} text
 */
function anchorPatterns(inline, text) {
  const target = inline.target ?? ''

  if (inline.type === 'link' && target) {
    return unique([
      `link:${target}[${text}]`,
      `${target}[${text}]`,
      target.includes('://') ? `${target}[${text}]` : null,
      target,
    ])
  }

  if (inline.type === 'xref' && target) {
    const ref = target.replace(/^#/, '')
    return unique([
      `<<${ref},${text}>>`,
      `<<${ref}>>`,
      `xref:${ref}[${text}]`,
    ])
  }

  return []
}

/**
 * @param {Record<string, unknown> | undefined} attributes
 */
function kbdPatterns(attributes) {
  const keys = attributes?.keys
  if (!Array.isArray(keys) || keys.length === 0) return []

  return [`kbd:[${keys.join('+')}]`]
}

/**
 * @param {Record<string, unknown> | undefined} attributes
 */
function menuPatterns(attributes) {
  if (!attributes?.menu) return []

  const menu = String(attributes.menu)
  const submenus = Array.isArray(attributes.submenus) ? attributes.submenus.map(String) : []
  const menuitem = attributes.menuitem ? String(attributes.menuitem) : ''

  if (submenus.length === 0) {
    return unique([`menu:${menu}[${menuitem}]`, `menu:${menu}[]`])
  }

  const inner = [...submenus, menuitem].filter(Boolean).join(' > ')
  return [`menu:${menu}[${inner}]`]
}

/**
 * @param {Record<string, unknown> | undefined} attributes
 */
function buttonLabel(attributes) {
  if (typeof attributes?.text === 'string') return attributes.text
  if (typeof attributes?.label === 'string') return attributes.label
  return undefined
}

/**
 * @param {Array<string | null | undefined>} values
 */
function unique(values) {
  return [...new Set(values.filter(Boolean))]
}
