import { stripKbmemoMetadataFromHtml } from '@kbmemo/adoc-wysiwyg'

const BLOCK_CONTAINER_TAGS = new Set([
  'address', 'article', 'aside', 'blockquote', 'details', 'div', 'dl', 'fieldset',
  'figure', 'footer', 'form', 'header', 'main', 'nav', 'ol', 'p', 'pre', 'section',
  'table', 'ul',
])

const SKIP_TAGS = new Set(['script', 'style', 'noscript', 'meta', 'link', 'head', 'svg', 'iframe'])

/**
 * Convert clipboard HTML (web page fragment) to AsciiDoc.
 *
 * @param {string} html
 * @returns {string}
 */
export function webHtmlToAsciidoc(html) {
  const trimmed = stripKbmemoMetadataFromHtml(html.trim())
  if (!trimmed) return ''

  const doc = new DOMParser().parseFromString(trimmed, 'text/html')
  sanitizeTree(doc.body)

  /** @type {string[]} */
  const blocks = []
  for (const child of doc.body.childNodes) {
    const block = convertTopLevelNode(child)
    if (block) blocks.push(block)
  }

  return normalizeBlocks(blocks)
}

/**
 * @param {ParentNode} root
 */
function sanitizeTree(root) {
  for (const el of [...root.querySelectorAll('a.anchor, a[href^="#"]')]) {
    if (isDecorativeHeadingAnchor(el)) {
      el.remove()
    }
  }

  for (const el of [...root.querySelectorAll('*')]) {
    const tag = el.tagName.toLowerCase()
    if (SKIP_TAGS.has(tag)) {
      el.remove()
      continue
    }
    for (const attr of [...el.attributes]) {
      if (/^on/i.test(attr.name)) {
        el.removeAttribute(attr.name)
      }
    }
  }
}

/**
 * @param {string[]} blocks
 */
function normalizeBlocks(blocks) {
  return blocks
    .map((block) => block.replace(/\n{3,}/g, '\n\n').trim())
    .filter(Boolean)
    .join('\n\n')
}

/**
 * @param {Node} node
 * @returns {string | null}
 */
function convertTopLevelNode(node) {
  if (node.nodeType === Node.TEXT_NODE) {
    const text = normalizeWhitespace(node.textContent ?? '')
    return text || null
  }

  if (node.nodeType !== Node.ELEMENT_NODE) return null

  const el = /** @type {HTMLElement} */ (node)
  const tag = el.tagName.toLowerCase()

  if (tag === 'br') return null

  if (tag.startsWith('h') && tag.length === 2) {
    const level = Number(tag[1])
    if (level >= 1 && level <= 6) {
      const marker = level === 1 ? '=' : '='.repeat(level)
      const text = inlineText(el)
      return text ? `${marker} ${text}` : null
    }
  }

  if (tag === 'blockquote') {
    return convertQuoteBlock(el)
  }

  if (tag === 'pre') {
    return convertPreformatted(el)
  }

  if (tag === 'ul' || tag === 'ol') {
    return convertListElement(el, 0)
  }

  if (tag === 'table') {
    return convertTableElement(el)
  }

  if (tag === 'hr') {
    return "'''"
  }

  if (tag === 'figure') {
    return convertFigure(el)
  }

  if (tag === 'p' || tag === 'div' || tag === 'section' || tag === 'article' || tag === 'main' || tag === 'span') {
    if (containsBlockContent(el)) {
      return convertBlockChildren(el)
    }
    const inline = inlineContent(el)
    return inline || null
  }

  if (BLOCK_CONTAINER_TAGS.has(tag)) {
    return convertBlockChildren(el)
  }

  const inline = inlineContent(el)
  return inline || null
}

/**
 * @param {HTMLElement} el
 */
function containsBlockContent(el) {
  for (const child of el.children) {
    const tag = child.tagName.toLowerCase()
    if (BLOCK_CONTAINER_TAGS.has(tag)) return true
    if (tag.startsWith('h') && tag.length === 2 && tag[1] >= '1' && tag[1] <= '6') return true
  }
  return false
}

/**
 * @param {HTMLElement} container
 * @returns {string | null}
 */
function convertBlockChildren(container) {
  /** @type {string[]} */
  const blocks = []

  for (const child of container.childNodes) {
    const block = convertTopLevelNode(child)
    if (block) blocks.push(block)
  }

  return blocks.length ? normalizeBlocks(blocks) : null
}

/**
 * @param {HTMLElement} el
 */
function convertQuoteBlock(el) {
  const inner = convertBlockChildren(el) ?? inlineContent(el)
  const text = inner?.trim()
  if (!text) return null
  return `____\n${text}\n____`
}

/**
 * @param {HTMLElement} el
 */
function convertPreformatted(el) {
  const code = el.querySelector('code')
  const text = (code ?? el).textContent?.replace(/\n$/, '') ?? ''
  if (!text.trim()) return null

  const lang =
    code?.getAttribute('data-lang') ??
    code?.className.match(/(?:language|lang)-(\S+)/)?.[1] ??
    ''

  /** @type {string[]} */
  const lines = []
  if (lang) lines.push(`[source,${lang}]`)
  lines.push('----', text, '----')
  return lines.join('\n')
}

/**
 * @param {HTMLElement} list
 * @param {number} depth
 */
function convertListElement(list, depth) {
  const tag = list.tagName.toLowerCase()
  const items = [...list.children].filter((child) => child.tagName === 'LI')
  if (items.length === 0) return null

  return items
    .map((item, index) => convertListItem(item, tag === 'ol' ? `.${index + 1}` : '*'.repeat(depth + 1), depth))
    .filter(Boolean)
    .join('\n')
}

/**
 * @param {HTMLElement} item
 * @param {string} marker
 * @param {number} depth
 */
function convertListItem(item, marker, depth) {
  /** @type {string[]} */
  const lines = []
  let itemText = ''

  for (const child of item.childNodes) {
    if (child.nodeType === Node.ELEMENT_NODE) {
      const el = /** @type {HTMLElement} */ (child)
      const tag = el.tagName.toLowerCase()
      if (tag === 'ul' || tag === 'ol') continue
      itemText += inlineContent(el)
    } else if (child.nodeType === Node.TEXT_NODE) {
      itemText += child.textContent ?? ''
    }
  }

  const trimmed = normalizeWhitespace(itemText)
  if (trimmed) lines.push(`${marker} ${trimmed}`)

  for (const nested of item.children) {
    const tag = nested.tagName.toLowerCase()
    if (tag === 'ul') {
      const nestedList = convertListElement(nested, depth + 1)
      if (nestedList) lines.push(nestedList)
    } else if (tag === 'ol') {
      const nestedList = convertListElement(nested, depth + 1)
      if (nestedList) lines.push(nestedList)
    }
  }

  return lines.filter(Boolean).join('\n')
}

/**
 * @param {HTMLElement} table
 */
function convertTableElement(table) {
  /** @type {string[]} */
  const lines = ['|===']
  const rows = [...table.querySelectorAll('tr')]
  if (rows.length === 0) return null

  for (const row of rows) {
    const cells = [...row.querySelectorAll('th, td')]
    if (cells.length === 0) continue
    lines.push(`|${cells.map((cell) => ` ${inlineContent(cell)} `).join('|')}`)
  }

  lines.push('|===')
  return lines.join('\n')
}

/**
 * @param {HTMLElement} figure
 */
function convertFigure(figure) {
  const img = figure.querySelector('img')
  const caption = figure.querySelector('figcaption')?.textContent?.trim()
  if (img) {
    const imageLine = convertImageElement(img)
    if (imageLine && caption) return `${imageLine}\n\n_${caption}_`
    if (imageLine) return imageLine
  }

  return convertBlockChildren(figure)
}

/**
 * @param {string} src
 * @param {string} alt
 * @param {string} linkHref
 */
function formatLinkedImageAdoc(src, alt, linkHref) {
  const prefix = /^https?:\/\//i.test(src) ? 'image:' : 'image::'
  return `${prefix}${src}${formatImageMacroAttributes(alt, linkHref)}`
}

/**
 * @param {string} alt
 * @param {string} linkHref
 */
function formatImageMacroAttributes(alt, linkHref) {
  /** @type {string[]} */
  const parts = []
  if (alt) parts.push(quoteImageAlt(escapeImageAlt(alt)))
  if (linkHref) parts.push(`link=${linkHref}`)
  return parts.length ? `[${parts.join(', ')}]` : '[]'
}

/**
 * @param {string} text
 */
function escapeImageAlt(text) {
  return text.replace(/\\/g, '\\\\').replace(/\[/g, '\\[').replace(/\]/g, '\\]')
}

/**
 * @param {string} text
 */
function quoteImageAlt(text) {
  if (/[,"]/.test(text)) return `"${text.replace(/"/g, '""')}"`
  return text
}

/**
 * @param {HTMLElement} el
 */
function isDecorativeHeadingAnchor(el) {
  const href = el.getAttribute('href')?.trim() ?? ''
  if (!href.startsWith('#')) return false

  const children = [...el.children]
  if (children.length === 0 && !(el.textContent ?? '').trim()) return true
  return children.length > 0 && children.every((child) => child.tagName.toLowerCase() === 'svg')
}

/**
 * @param {HTMLAnchorElement} anchor
 * @returns {{ href: string, src: string, alt: string } | null}
 */
function linkedImageFromAnchor(anchor) {
  const children = [...anchor.children]
  if (children.length !== 1 || children[0].tagName.toLowerCase() !== 'img') return null

  const img = /** @type {HTMLImageElement} */ (children[0])
  const href = anchor.getAttribute('href')?.trim() ?? ''
  const src = img.getAttribute('src')?.trim() ?? ''
  if (!href || !src) return null

  return { href, src, alt: img.getAttribute('alt')?.trim() ?? '' }
}

/**
 * @param {HTMLImageElement} img
 */
function convertImageElement(img) {
  const src = img.getAttribute('src')?.trim() ?? ''
  const alt = img.getAttribute('alt')?.trim() ?? ''
  if (!src) return alt || null

  if (/^https?:\/\//i.test(src)) {
    if (alt) return `link:${src}[${escapeLinkLabel(alt)}]`
    return src
  }

  if (alt) return `image::${src}[${escapeLinkLabel(alt)}]`
  return `image::${src}[]`
}

/**
 * @param {HTMLElement} el
 */
function inlineText(el) {
  return normalizeWhitespace(inlineContent(el))
}

/**
 * @param {Node} node
 */
function inlineContent(node) {
  /** @type {string[]} */
  const parts = []

  for (const child of node.childNodes) {
    parts.push(inlineNode(child))
  }

  return parts.join('')
}

/**
 * @param {Node} node
 */
function inlineNode(node) {
  if (node.nodeType === Node.TEXT_NODE) {
    return node.textContent ?? ''
  }

  if (node.nodeType !== Node.ELEMENT_NODE) return ''

  const el = /** @type {HTMLElement} */ (node)
  const tag = el.tagName.toLowerCase()

  if (tag === 'br') return '\n'

  if (tag === 'img') {
    return convertImageElement(/** @type {HTMLImageElement} */ (el)) ?? ''
  }

  const inner = inlineContent(el)
  if (!inner && tag !== 'img') return ''

  if (tag === 'strong' || tag === 'b') return inner ? `*${inner.trim()}*` : ''
  if (tag === 'em' || tag === 'i') return inner ? `_${inner.trim()}_` : ''
  if (tag === 'code' || tag === 'kbd') return inner ? `\`${inner.trim()}\`` : ''
  if (tag === 'a') {
    if (isDecorativeHeadingAnchor(el)) return ''

    const linked = linkedImageFromAnchor(/** @type {HTMLAnchorElement} */ (el))
    if (linked) {
      const link = linked.href !== linked.src ? linked.href : ''
      return formatLinkedImageAdoc(linked.src, linked.alt, link)
    }

    const href = el.getAttribute('href')?.trim() ?? ''
    if (!href) return inner
    const label = inner.trim()
    if (label && label !== href) return `link:${href}[${escapeLinkLabel(label)}]`
    return href
  }

  if (tag === 'span' || tag === 'font') return inner

  if (tag.startsWith('h') && tag.length === 2) {
    return inner.trim()
  }

  if (BLOCK_CONTAINER_TAGS.has(tag)) {
    return convertBlockChildren(el) ?? inner
  }

  return inner
}

/**
 * @param {string} text
 */
function normalizeWhitespace(text) {
  return text.replace(/\u00a0/g, ' ').replace(/[ \t]+\n/g, '\n').replace(/\n[ \t]+/g, '\n').trim()
}

/**
 * @param {string} text
 */
function escapeLinkLabel(text) {
  return text.replace(/\\/g, '\\\\').replace(/\[/g, '\\[').replace(/\]/g, '\\]')
}
