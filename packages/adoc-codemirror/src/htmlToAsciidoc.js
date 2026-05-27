import { diagramMacroPathFromSvgRelative } from '@kbmemo/adoc-kbmemo'
import { memoAssetRelativePath } from '@kbmemo/adoc-kbmemo'
import { getUnitAdocSource } from '@kbmemo/adoc-wysiwyg'
import {
  INDENT_LITERAL_DATA_ATTR,
  indentLiteralFromPlainText,
  normalizeBlockSegmentText,
} from './literalParagraph.js'
import {
  formatHardBreakLine,
  isEmptyParagraphMarkerBr,
} from './hardbreakParagraph.js'

/**
 * Convert Asciidoctor HTML5 output (preview body) back to AsciiDoc.
 * Covers common blocks for WYSIWYG round-trip; complex markup may be lossy.
 *
 * @param {ParentNode} root
 * @param {{ getSourceValue?: (host: HTMLElement) => string, memoId?: string | null }} [options]
 * @returns {string}
 */
export function htmlToAsciidoc(root, { getSourceValue, memoId } = {}) {
  /** @type {string[]} */
  const blocks = []

  for (const node of root.childNodes) {
    if (node.nodeType === Node.ELEMENT_NODE && node.classList.contains('wysiwyg-unit')) {
      const unitEl = /** @type {HTMLElement} */ (node)
      const sourceHost = unitEl.querySelector(':scope > .wysiwyg-source-editor')
      if (sourceHost instanceof HTMLElement && unitEl.classList.contains('is-source')) {
        const text = getSourceValue?.(sourceHost) ?? sourceHost.textContent ?? ''
        const normalized = normalizeBlockSegmentText(text)
        if (normalized) blocks.push(normalized)
        continue
      }
      const block = unitToAsciidoc(unitEl, memoId)
      if (block) blocks.push(block)
      continue
    }

    const block = convertNode(node, memoId)
    if (block) blocks.push(block)
  }

  const body = blocks.join('\n\n').trimEnd()
  return body + (body ? '\n' : '')
}

/**
 * @param {HTMLElement} unitEl
 * @param {string | null | undefined} [memoId]
 * @returns {string}
 */
export function unitToAsciidoc(unitEl, memoId) {
  if (unitEl.classList.contains('wysiwyg-unit')) {
    const stored = getUnitAdocSource(unitEl)
    if (stored !== undefined) return stored
    if (typeof console !== 'undefined' && console.warn) {
      console.warn(
        '[kbmemo wysiwyg] wysiwyg-unit has no stored AsciiDoc source; skipping HTML recovery',
      )
    }
    return ''
  }

  /** @type {string[]} */
  const parts = []

  for (const child of unitEl.childNodes) {
    if (child.nodeType === Node.ELEMENT_NODE && child.classList.contains('wysiwyg-source-editor')) {
      continue
    }
    const part = convertNode(child, memoId)
    if (part) parts.push(part)
  }

  return parts.join('\n\n')
}

/**
 * @param {Node} node
 * @param {string | null | undefined} [memoId]
 * @returns {string | null}
 */
function convertNode(node, memoId) {
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
    return convertParagraph(el)
  }

  if (el.classList.contains('ulist')) {
    return convertList(el)
  }

  if (el.classList.contains('olist')) {
    return convertOrderedList(el)
  }

  if (el.classList.contains('tableblock')) {
    return convertTable(el)
  }

  if (el.classList.contains('listingblock')) {
    return convertListing(el)
  }

  if (el.classList.contains('literalblock')) {
    const pre = el.querySelector('pre')
    const text = pre?.textContent ?? el.textContent ?? ''
    if (!text.trim()) return null

    if (el.dataset[INDENT_LITERAL_DATA_ATTR] === 'true') {
      return indentLiteralFromPlainText(text)
    }

    return `....\n${text.trim()}\n....`
  }

  if (el.classList.contains('imageblock')) {
    return convertImage(el, memoId)
  }

  if (el.classList.contains('admonitionblock')) {
    return convertAdmonition(el)
  }

  if (el.classList.contains('stemblock')) {
    return convertStemBlock(el)
  }

  if (el.classList.contains('quoteblock')) {
    const quote = el.querySelector('blockquote') ?? el
    return `____\n${quote.textContent?.trim() ?? ''}\n____`
  }

  if (/^sect[0-4]$/.test(el.className.split(/\s+/)[0] ?? '') || el.classList.contains('sect5')) {
    return convertSection(el, memoId)
  }

  if (tag === 'div' || tag === 'section') {
    /** @type {string[]} */
    const parts = []
    for (const child of el.childNodes) {
      const part = convertNode(child, memoId)
      if (part) parts.push(part)
    }
    return parts.length ? parts.join('\n\n') : null
  }

  const inline = inlineContent(el)
  return inline || null
}

/**
 * @param {HTMLElement} section
 * @param {string | null | undefined} [memoId]
 */
function convertSection(section, memoId) {
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
    const block = convertNode(child, memoId)
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
 * @param {string | null | undefined} [memoId]
 */
function convertImage(block, memoId) {
  const obj = block.querySelector('object[data]')
  const img = block.querySelector('img')
  const raw =
    obj?.getAttribute('data-filename') ||
    obj?.getAttribute('data') ||
    img?.getAttribute('data-filename') ||
    img?.getAttribute('src') ||
    ''
  const src = memoAssetRelativePath(memoId, raw) || raw

  const diagramMacro = diagramMacroPathFromSvgRelative(src)
  if (diagramMacro) {
    return `diagram::${diagramMacro}[]`
  }

  const alt = img?.getAttribute('alt') ?? obj?.querySelector('.alt')?.textContent?.trim() ?? ''
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
 * @param {HTMLElement} block
 */
function convertStemBlock(block) {
  const title = block.querySelector('.title')?.textContent?.trim()
  const content = block.querySelector('.content')?.textContent?.trim() ?? ''
  /** @type {string[]} */
  const lines = []
  if (title) lines.push(`.${title}`)
  lines.push('[stem]', '++++', content, '++++')
  return lines.join('\n')
}

/**
 * @param {HTMLElement} list
 * @param {number} [depth]
 */
function convertList(list, depth = 0) {
  const marker = '*'.repeat(depth + 1)
  const ul = list.tagName === 'UL' ? list : list.querySelector(':scope > ul')
  if (!ul) return null

  return [...ul.children]
    .filter((el) => el.tagName === 'LI')
    .map((item) => convertListItem(item, marker, depth))
    .join('\n')
}

function convertOrderedList(list, depth = 0) {
  const ol = list.tagName === 'OL' ? list : list.querySelector(':scope > ol')
  if (!ol) return null

  return [...ol.children]
    .filter((el) => el.tagName === 'LI')
    .map((item, index) => convertListItem(item, `.${index + 1}`, depth))
    .join('\n')
}

function convertListItem(item, marker, depth) {
  /** @type {string[]} */
  const lines = []
  let itemText = ''

  for (const child of item.childNodes) {
    if (child.nodeType === Node.ELEMENT_NODE) {
      const el = /** @type {HTMLElement} */ (child)
      if (el.classList.contains('ulist') || el.classList.contains('olist')) continue
      itemText += inlineContent(el)
    } else if (child.nodeType === Node.TEXT_NODE) {
      itemText += child.textContent ?? ''
    }
  }

  lines.push(`${marker} ${itemText.trim()}`)

  for (const nested of item.querySelectorAll(':scope > .ulist, :scope > .olist')) {
    if (nested.classList.contains('ulist')) {
      lines.push(convertList(nested, depth + 1))
    } else {
      lines.push(convertOrderedList(nested, depth + 1))
    }
  }

  return lines.filter(Boolean).join('\n')
}

/**
 * @param {HTMLElement} block
 */
function convertTable(block) {
  const table = block.querySelector('table.tableblock, table')
  if (!table) return block.textContent?.trim() ?? null

  /** @type {string[]} */
  const lines = []
  const title = block.querySelector(':scope > .title')?.textContent?.trim()
  if (title) lines.push(`.${title}`)

  const caption = block.querySelector('caption')?.textContent?.trim()
  if (caption) lines.push(`[caption=${caption}]`)

  lines.push('|===')

  for (const row of table.querySelectorAll('tr')) {
    const cells = [...row.querySelectorAll('th, td')]
    if (cells.length === 0) continue
    lines.push(`|${cells.map((cell) => ` ${inlineContent(cell)} `).join('|')}`)
  }

  lines.push('|===')
  return lines.join('\n')
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

const HARDBREAKS_DATA_ATTR = 'kbHardbreaks'
const LEAD_DATA_ATTR = 'kbLead'

/**
 * @param {HTMLElement} wrapper
 */
function convertParagraph(wrapper) {
  const hardbreaks = wrapper.dataset[HARDBREAKS_DATA_ATTR] === 'true'
  const lead =
    wrapper.dataset[LEAD_DATA_ATTR] === 'true' || wrapper.classList.contains('lead')
  const p = wrapper.querySelector('p') ?? wrapper
  const body = serializeParagraphBody(p, { hardbreaks })
  if (!body) return null
  if (hardbreaks) return `[%hardbreaks]\n${body}`
  if (lead) return `[.lead]\n${body}`
  return body
}

/**
 * @param {HTMLElement} p
 * @param {{ hardbreaks: boolean }} options
 */
function serializeParagraphBody(p, { hardbreaks }) {
  /** @type {string[]} */
  const lines = []
  let current = ''

  const pushLine = () => {
    if (hardbreaks) {
      lines.push(current)
    } else {
      const formatted = formatHardBreakLine(current)
      if (formatted) lines.push(formatted)
    }
    current = ''
  }

  for (const child of p.childNodes) {
    if (child.nodeType === Node.TEXT_NODE) {
      let text = child.textContent ?? ''
      if (current === '' && lines.length > 0) {
        text = text.replace(/^\n+/, '')
      }
      current += text
      continue
    }

    if (child.nodeType !== Node.ELEMENT_NODE) continue

    const el = /** @type {HTMLElement} */ (child)
    const tag = el.tagName.toLowerCase()

    if (tag === 'br') {
      if (isEmptyParagraphMarkerBr(el)) continue
      pushLine()
      continue
    }

    current += inlineNode(el)
  }

  const trailing = hardbreaks ? current : current.replace(/\s+$/, '')
  if (trailing || lines.length === 0) {
    lines.push(trailing)
  }

  return lines.join('\n').trimEnd()
}

/**
 * @param {HTMLElement} el
 */
function inlineText(el) {
  return el.textContent?.trim() ?? ''
}
