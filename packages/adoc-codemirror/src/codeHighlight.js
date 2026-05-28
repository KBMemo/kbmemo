import hljs from 'highlight.js/lib/core'
import bash from 'highlight.js/lib/languages/bash'
import c from 'highlight.js/lib/languages/c'
import cpp from 'highlight.js/lib/languages/cpp'
import csharp from 'highlight.js/lib/languages/csharp'
import css from 'highlight.js/lib/languages/css'
import go from 'highlight.js/lib/languages/go'
import java from 'highlight.js/lib/languages/java'
import javascript from 'highlight.js/lib/languages/javascript'
import json from 'highlight.js/lib/languages/json'
import markdown from 'highlight.js/lib/languages/markdown'
import python from 'highlight.js/lib/languages/python'
import ruby from 'highlight.js/lib/languages/ruby'
import rust from 'highlight.js/lib/languages/rust'
import sql from 'highlight.js/lib/languages/sql'
import typescript from 'highlight.js/lib/languages/typescript'
import xml from 'highlight.js/lib/languages/xml'
import yaml from 'highlight.js/lib/languages/yaml'

/** @typedef {{ from: number, to: number, className: string }} CodeSpan */

const LANGUAGE_ALIASES = {
  js: 'javascript',
  ts: 'typescript',
  py: 'python',
  rb: 'ruby',
  sh: 'bash',
  shell: 'bash',
  yml: 'yaml',
  html: 'xml',
  adoc: 'markdown',
  asciidoc: 'markdown',
}

const REGISTERED = [
  ['bash', bash],
  ['c', c],
  ['cpp', cpp],
  ['csharp', csharp],
  ['css', css],
  ['go', go],
  ['java', java],
  ['javascript', javascript],
  ['json', json],
  ['markdown', markdown],
  ['python', python],
  ['ruby', ruby],
  ['rust', rust],
  ['sql', sql],
  ['typescript', typescript],
  ['xml', xml],
  ['yaml', yaml],
]

let initialized = false

function ensureLanguagesRegistered() {
  if (initialized) return
  for (const [name, language] of REGISTERED) {
    hljs.registerLanguage(name, language)
  }
  initialized = true
}

/**
 * @param {string | undefined | null} language
 */
export function normalizeLanguage(language) {
  if (!language) return 'plaintext'
  const normalized = String(language).trim().toLowerCase()
  return LANGUAGE_ALIASES[normalized] ?? normalized
}

/**
 * @param {string} code
 * @param {string | undefined | null} language
 * @returns {{ html: string, spans: CodeSpan[] }}
 */
export function highlightCode(code, language) {
  ensureLanguagesRegistered()
  const lang = normalizeLanguage(language)

  let html
  if (lang === 'plaintext' || !hljs.getLanguage(lang)) {
    html = escapeHtml(code)
  } else {
    html = hljs.highlight(code, { language: lang, ignoreIllegals: true }).value
  }

  return { html, spans: htmlToSpans(html) }
}

/**
 * Asciidoctor (source-highlighter) may already embed syntax spans and callout markers.
 * Re-highlighting strips `.conum` badges and drops callout numbers in live preview.
 *
 * @param {HTMLElement} block
 */
function isAlreadySyntaxHighlighted(block) {
  if (block.querySelector('.conum, i.conum')) return true
  return block.querySelector('[class*="hljs-"]') != null
}

/**
 * @param {ParentNode} container
 */
export function highlightPreviewCode(container) {
  ensureLanguagesRegistered()
  container.querySelectorAll('pre code[data-lang], pre code[class*="language-"]').forEach((block) => {
    if (isAlreadySyntaxHighlighted(block)) return
    hljs.highlightElement(block)
  })
}

/**
 * @param {string} html
 * @returns {CodeSpan[]}
 */
function htmlToSpans(html) {
  /** @type {CodeSpan[]} */
  const spans = []
  const doc = new DOMParser().parseFromString(`<div>${html}</div>`, 'text/html')
  walkNodes(doc.body.firstElementChild, 0, [], spans)
  return spans
}

/**
 * @param {Node | null} node
 * @param {number} offset
 * @param {string[]} classStack
 * @param {CodeSpan[]} spans
 * @returns {number}
 */
function walkNodes(node, offset, classStack, spans) {
  if (!node) return offset

  if (node.nodeType === Node.TEXT_NODE) {
    const text = node.textContent ?? ''
    if (text && classStack.length > 0) {
      spans.push({
        from: offset,
        to: offset + text.length,
        className: classStack[classStack.length - 1],
      })
    }
    return offset + text.length
  }

  if (node.nodeType !== Node.ELEMENT_NODE) {
    return offset
  }

  const element = /** @type {HTMLElement} */ (node)
  const nextStack = element.tagName === 'SPAN' && element.className
    ? [...classStack, toEditorClass(element.className)]
    : classStack

  let nextOffset = offset
  for (const child of element.childNodes) {
    nextOffset = walkNodes(child, nextOffset, nextStack, spans)
  }
  return nextOffset
}

/**
 * @param {string} className
 */
function toEditorClass(className) {
  const hljsClass = className.split(/\s+/).find((name) => name.startsWith('hljs-'))
  return hljsClass ? `cm-${hljsClass}` : 'cm-hljs'
}

/**
 * @param {string} value
 */
function escapeHtml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
}
