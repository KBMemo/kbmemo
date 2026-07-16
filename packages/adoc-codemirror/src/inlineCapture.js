import { Inline } from '@asciidoctor/core'

/** @typedef {{ context: string, type?: string, text?: string, target?: string, attributes?: Record<string, unknown> }} CapturedInline */

/** Serialize capture runs — Inline.prototype.convert is patched globally. */
let captureTail = Promise.resolve()

/**
 * @param {import('@asciidoctor/core').AbstractNode} node
 * @param {string} text
 * @returns {Promise<CapturedInline[]>}
 */
export function captureInlines(node, text) {
  const run = async () => {
    const captured = []
    const originalConvert = Inline.prototype.convert

    Inline.prototype.convert = async function captureInlineConvert() {
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
      await node.applySubs(text)
    } finally {
      Inline.prototype.convert = originalConvert
    }

    return captured
  }

  const job = captureTail.then(run, run)
  captureTail = job.then(
    () => {},
    () => {},
  )
  return job
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
      case 'mark':
      case 'unquoted':
        return 'adoc-highlight'
      case 'superscript':
        return 'adoc-superscript'
      case 'subscript':
        return 'adoc-subscript'
      default:
        return 'adoc-inline'
    }
  }

  if (inline.context === 'anchor') {
    switch (inline.type) {
      case 'link':
        return 'adoc-link'
      case 'xref':
        return 'adoc-xref'
      case 'ref':
        return 'adoc-anchor'
      default:
        return 'adoc-link'
    }
  }

  if (inline.context === 'kbd') return 'adoc-kbd'
  if (inline.context === 'menu') return 'adoc-menu'
  if (inline.context === 'button') return 'adoc-button'
  if (inline.context === 'footnote') return 'adoc-footnote'

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

  if (inline.context === 'anchor') {
    return findAnchorMarkup(blockText, inline, fromIndex)
  }

  if (inline.context === 'footnote') {
    return findFootnoteMarkup(blockText, inline, fromIndex)
  }

  return null
}

/**
 * @param {string} blockText
 * @param {CapturedInline} inline
 * @param {number} fromIndex
 */
function findAnchorMarkup(blockText, inline, fromIndex) {
  const slice = blockText.slice(fromIndex)

  if (inline.type === 'ref') {
    const refMatch = slice.match(/^(?:\[\[[^\],]+\]\]|anchor:[^\[]+\[\])/)
    if (refMatch) {
      return { from: fromIndex, to: fromIndex + refMatch[0].length }
    }
  }

  if (inline.type === 'xref' && inline.text) {
    const label = `[${inline.text}]`
    const labelIndex = blockText.indexOf(label, fromIndex)
    if (labelIndex >= 0) {
      const before = blockText.slice(fromIndex, labelIndex)
      const xrefStart = before.lastIndexOf('xref:')
      if (xrefStart >= 0) {
        return { from: fromIndex + xrefStart, to: labelIndex + label.length }
      }

      const angleMatch = before.match(/<<[^>]*$/)
      if (angleMatch) {
        return { from: fromIndex + before.length - angleMatch[0].length, to: labelIndex + label.length }
      }
    }
  }

  return null
}

/**
 * @param {string} blockText
 * @param {CapturedInline} inline
 * @param {number} fromIndex
 */
function findFootnoteMarkup(blockText, inline, fromIndex) {
  const patterns = footnotePatterns(inline)

  for (const pattern of patterns) {
    const index = blockText.indexOf(pattern, fromIndex)
    if (index >= 0) {
      return { from: index, to: index + pattern.length }
    }
  }

  const slice = blockText.slice(fromIndex)
  const generic = slice.match(/[!.]footnote(?::\w+)?(?:\[[^\]]*\])?/)
  if (generic) {
    return { from: fromIndex + generic.index, to: fromIndex + generic.index + generic[0].length }
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
    return quotedPatterns(inline.type, text, inline.attributes)
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
    const label = inline.text ?? buttonLabel(inline.attributes)
    return label ? [`btn:[${label}]`] : []
  }

  if (inline.context === 'footnote') {
    return footnotePatterns(inline)
  }

  return []
}

/**
 * @param {string | undefined} type
 * @param {string} text
 * @param {Record<string, unknown> | undefined} attributes
 */
function quotedPatterns(type, text, attributes = {}) {
  switch (type) {
    case 'strong':
      return [`**${text}**`, `*${text}*`]
    case 'emphasis':
      return [`__${text}__`, `_${text}_`]
    case 'monospaced':
      return [`\`${text}\``, `\`\`${text}\`\``, `+${text}+`]
    case 'passthrough':
      return [`+${text}+`, `\`${text}\``]
    case 'mark':
      return [`#${text}#`]
    case 'superscript':
      return [`^${text}^`]
    case 'subscript':
      return [`~${text}~`]
    case 'unquoted': {
      const role = attributes?.role
      if (typeof role === 'string' && role.length > 0) {
        return [`[.${role}]#${text}#`, `#${text}#`]
      }
      return [`#${text}#`]
    }
    default:
      return [`*${text}*`, `_${text}_`, `\`${text}\``, `#${text}#`]
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
      text ? `<<${ref},${text}>>` : null,
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
 * @param {CapturedInline} inline
 */
function footnotePatterns(inline) {
  const text = inline.text ?? ''
  if (inline.type === 'xref' && text) {
    return unique([
      `footnote:${text}[]`,
      `.footnote:${text}[]`,
      `!footnote:${text}[]`,
      `footnote:${text}[${text}]`,
    ])
  }

  if (text) {
    return unique([
      `footnote:[${text}]`,
      `.footnote:[${text}]`,
      `!footnote:[${text}]`,
    ])
  }

  return []
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
