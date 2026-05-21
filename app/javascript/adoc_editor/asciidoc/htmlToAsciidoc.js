/**
 * Convert Asciidoctor HTML5 output (preview body) back to AsciiDoc.
 * Covers common blocks for WYSIWYG round-trip; complex markup may be lossy.
 *
 * @param {ParentNode} root
 * @param {{ getSourceValue?: (host: HTMLElement) => string }} [options]
 * @returns {string}
 */
export function htmlToAsciidoc(root, { getSourceValue } = {}) {
  /** @type {string[]} */
  const blocks = []

  for (const node of root.childNodes) {
    if (node.nodeType === Node.ELEMENT_NODE && node.classList.contains('wysiwyg-unit')) {
      const unitEl = /** @type {HTMLElement} */ (node)
      const sourceHost = unitEl.querySelector(':scope > .wysiwyg-source-editor')
      if (sourceHost instanceof HTMLElement && unitEl.classList.contains('is-source')) {
        const text = (getSourceValue?.(sourceHost) ?? sourceHost.textContent ?? '').trim()
        if (text) blocks.push(text)
        continue
      }
      const block = unitToAsciidoc(unitEl)
      if (block) blocks.push(block)
      continue
    }

    const block = convertNode(node)
    if (block) blocks.push(block)
  }

  return blocks.join('\n\n').trim() + (blocks.length ? '\n' : '')
}

/**
 * @param {HTMLElement} unitEl
 * @returns {string}
 */
export function unitToAsciidoc(unitEl) {
  /** @type {string[]} */
  const parts = []

  for (const child of unitEl.childNodes) {
    if (child.nodeType === Node.ELEMENT_NODE && child.classList.contains('wysiwyg-source-editor')) {
      continue
    }
    const part = convertNode(child)
    if (part) parts.push(part)
  }

  return parts.join('\n\n')
}

/**
 * @param {Node} node
 * @returns {string | null}
 */
function convertNode(node) {
  if (node.nodeType === Node.TEXT_NODE) {
    const text = node.textContent?.trim()
    return text || null
  }

  if (node.nodeType !== Node.ELEMENT_NODE) return null

  const el = /** @type {HTMLElement} */ (node)
  const tag = el.tagName.toLowerCase()

  if (tag === 'h1') return `= ${inlineText(el)}`
  if (tag.startsWith('h') && tag.length === 2) {
    const level = Number(tag[1])
    if (level >= 2 && level <= 6) {
      return `${'='.repeat(level)} ${inlineText(el)}`
    }
  }

  if (el.classList.contains('paragraph')) {
    const p = el.querySelector('p')
    return p ? inlineContent(p) : inlineContent(el)
  }

  if (el.classList.contains('ulist')) {
    return convertList(el)
  }

  if (el.classList.contains('olist')) {
    return convertOrderedList(el)
  }

  if (el.classList.contains('listingblock')) {
    return convertListing(el)
  }

  if (el.classList.contains('literalblock')) {
    const pre = el.querySelector('pre')
    const text = pre?.textContent ?? el.textContent ?? ''
    return `....\n${text.trim()}\n....`
  }

  if (el.classList.contains('imageblock')) {
    return convertImage(el)
  }

  if (el.classList.contains('admonitionblock')) {
    return convertAdmonition(el)
  }

  if (el.classList.contains('quoteblock')) {
    const quote = el.querySelector('blockquote') ?? el
    return `____\n${quote.textContent?.trim() ?? ''}\n____`
  }

  if (/^sect[0-4]$/.test(el.className.split(/\s+/)[0] ?? '') || el.classList.contains('sect5')) {
    return convertSection(el)
  }

  if (tag === 'div' || tag === 'section') {
    /** @type {string[]} */
    const parts = []
    for (const child of el.childNodes) {
      const part = convertNode(child)
      if (part) parts.push(part)
    }
    return parts.length ? parts.join('\n\n') : null
  }

  const inline = inlineContent(el)
  return inline || null
}

/**
 * @param {HTMLElement} section
 */
function convertSection(section) {
  const heading = section.querySelector(':scope > h1, :scope > h2, :scope > h3, :scope > h4, :scope > h5, :scope > h6')
  /** @type {string[]} */
  const parts = []

  if (heading) {
    const level = Number(heading.tagName[1])
    parts.push(`${'='.repeat(level)} ${inlineText(heading)}`)
  }

  const body = section.querySelector(':scope > .sectionbody') ?? section
  for (const child of body.childNodes) {
    if (child === heading) continue
    const block = convertNode(child)
    if (block) parts.push(block)
  }

  return parts.join('\n\n')
}

/**
 * @param {HTMLElement} block
 */
function convertListing(block) {
  const code = block.querySelector('code')
  const pre = block.querySelector('pre')
  const text = (code ?? pre)?.textContent ?? ''
  const lang = code?.getAttribute('data-lang') ?? code?.className.match(/language-(\S+)/)?.[1] ?? ''
  const title = block.querySelector('.title')?.textContent?.trim()

  /** @type {string[]} */
  const lines = []
  if (title) lines.push(`.${title}`)
  if (lang) lines.push(`[source,${lang}]`)
  lines.push('----', text.replace(/\n$/, ''), '----')
  return lines.join('\n')
}

/**
 * @param {HTMLElement} block
 */
function convertImage(block) {
  const img = block.querySelector('img')
  if (!img) return null
  const src = img.getAttribute('data-filename') || img.getAttribute('src') || ''
  const alt = img.getAttribute('alt') ?? ''
  return `image::${src}[${alt}]`
}

/**
 * @param {HTMLElement} block
 */
function convertAdmonition(block) {
  const type = [...block.classList].find((name) => /^(note|tip|important|warning|caution)$/.test(name)) ?? 'note'
  const label = type.toUpperCase()
  const content = block.querySelector('.content') ?? block
  const text = content.textContent?.trim() ?? ''
  return `${label}: ${text}`
}

/**
 * @param {HTMLElement} list
 */
function convertList(list) {
  const items = list.querySelectorAll('li')
  return [...items]
    .map((item) => {
      const p = item.querySelector('p') ?? item
      return `* ${inlineContent(p)}`
    })
    .join('\n')
}

/**
 * @param {HTMLElement} list
 */
function convertOrderedList(list) {
  const items = list.querySelectorAll('li')
  return [...items]
    .map((item, index) => {
      const p = item.querySelector('p') ?? item
      return `.${index + 1} ${inlineContent(p)}`
    })
    .join('\n')
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

  return parts.join('').replace(/\u00a0/g, ' ').trim()
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
  const inner = inlineContent(el)

  if (tag === 'strong' || tag === 'b') return inner ? `*${inner}*` : ''
  if (tag === 'em' || tag === 'i') return inner ? `_${inner}_` : ''
  if (tag === 'code') return inner ? `\`${inner}\`` : ''
  if (tag === 'a') {
    const href = el.getAttribute('href') ?? ''
    if (!href) return inner
    if (inner && inner !== href) return `link:${href}[${inner}]`
    return href
  }
  if (tag === 'br') return '\n'
  if (tag === 'kbd') return el.textContent ? `kbd:[${el.textContent}]` : inner

  return inner
}

/**
 * @param {HTMLElement} el
 */
function inlineText(el) {
  return el.textContent?.trim() ?? ''
}
