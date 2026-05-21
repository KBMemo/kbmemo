import {
  SearchQuery,
  findNext,
  findPrevious,
  replaceAll,
  replaceNext,
  setSearchQuery,
} from '@codemirror/search'
import {
  findDocumentMatches,
  pickNextDocumentMatch,
  replaceAllInDocument,
  replaceDocumentMatch,
} from './wysiwygDocumentSearch.js'

/** @typedef {import('./wysiwygDocumentSearch.js').DocumentMatch} DocumentMatch */

/** @typedef {{
 *   getDocument: () => string
 *   getCursorPosition: () => number
 *   getSelectedText: () => string
 *   applyDocument: (source: string) => void
 *   revealMatch: (from: number, to: number) => void
 * }} DocumentSearchController */

/** @type {{ type: 'codemirror', view: import('@codemirror/view').EditorView } | { type: 'document', controller: DocumentSearchController } | null} */
let activeTarget = null

/** @type {HTMLElement | null} */
let dialogEl = null

/** @type {number} */
let documentMatchIndex = -1

/**
 * @param {{ onClose?: () => void }} [options]
 */
export function createSearchReplaceDialog({ onClose } = {}) {
  if (dialogEl) return dialogEl

  dialogEl = document.createElement('div')
  dialogEl.className = 'search-replace-dialog'
  dialogEl.hidden = true
  dialogEl.innerHTML = `
    <form class="search-replace-form">
      <div class="search-replace-header">
        <div>
          <strong>検索・置換</strong>
          <p class="search-replace-scope"></p>
        </div>
        <button type="button" class="search-replace-close" aria-label="閉じる">×</button>
      </div>
      <label class="search-replace-field">
        <span>検索</span>
        <input type="text" class="search-input" autocomplete="off" spellcheck="false" />
      </label>
      <label class="search-replace-field">
        <span>置換</span>
        <input type="text" class="replace-input" autocomplete="off" spellcheck="false" />
      </label>
      <label class="search-replace-option">
        <input type="checkbox" class="case-sensitive-input" />
        大文字と小文字を区別
      </label>
      <div class="search-replace-actions">
        <button type="button" data-action="prev">前を検索</button>
        <button type="button" data-action="next">次を検索</button>
        <button type="button" data-action="replace">置換</button>
        <button type="button" data-action="replace-all">すべて置換</button>
      </div>
      <p class="search-replace-status" aria-live="polite"></p>
    </form>
  `
  document.body.append(dialogEl)

  const form = /** @type {HTMLFormElement} */ (dialogEl.querySelector('.search-replace-form'))
  const searchInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.search-input'))
  const replaceInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.replace-input'))
  const caseInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.case-sensitive-input'))
  const statusEl = /** @type {HTMLElement} */ (dialogEl.querySelector('.search-replace-status'))

  form.addEventListener('submit', (event) => {
    event.preventDefault()
    runFindNext()
  })

  dialogEl.querySelector('.search-replace-close')?.addEventListener('click', () => {
    closeSearchReplaceDialog()
    onClose?.()
  })

  for (const button of dialogEl.querySelectorAll('[data-action]')) {
    button.addEventListener('click', () => {
      const action = button.getAttribute('data-action')
      if (action === 'prev') runFindPrevious()
      if (action === 'next') runFindNext()
      if (action === 'replace') runReplaceNext()
      if (action === 'replace-all') runReplaceAll()
    })
  }

  searchInput.addEventListener('input', () => {
    documentMatchIndex = -1
    syncQuery()
  })
  replaceInput.addEventListener('input', syncQuery)
  caseInput.addEventListener('change', () => {
    documentMatchIndex = -1
    syncQuery()
  })

  function syncQuery() {
    if (activeTarget?.type === 'codemirror') {
      applyQuery(
        activeTarget.view,
        searchInput.value,
        replaceInput.value,
        caseInput.checked,
      )
    }
    statusEl.textContent = ''
  }

  function runFindNext() {
    if (!searchInput.value) {
      statusEl.textContent = '検索文字列を入力してください'
      return
    }

    if (activeTarget?.type === 'codemirror') {
      if (!applyQuery(activeTarget.view, searchInput.value, replaceInput.value, caseInput.checked)) return
      statusEl.textContent = findNext(activeTarget.view) ? '' : '一致するものが見つかりません'
      return
    }

    if (activeTarget?.type === 'document') {
      const found = findInDocument(activeTarget.controller, false)
      statusEl.textContent = found ? formatDocumentMatchStatus(activeTarget.controller) : '一致するものが見つかりません'
    }
  }

  function runFindPrevious() {
    if (!searchInput.value) {
      statusEl.textContent = '検索文字列を入力してください'
      return
    }

    if (activeTarget?.type === 'codemirror') {
      if (!applyQuery(activeTarget.view, searchInput.value, replaceInput.value, caseInput.checked)) return
      statusEl.textContent = findPrevious(activeTarget.view) ? '' : '一致するものが見つかりません'
      return
    }

    if (activeTarget?.type === 'document') {
      const found = findInDocument(activeTarget.controller, true)
      statusEl.textContent = found ? formatDocumentMatchStatus(activeTarget.controller) : '一致するものが見つかりません'
    }
  }

  function runReplaceNext() {
    if (!searchInput.value) {
      statusEl.textContent = '検索文字列を入力してください'
      return
    }

    if (activeTarget?.type === 'codemirror') {
      if (!applyQuery(activeTarget.view, searchInput.value, replaceInput.value, caseInput.checked)) return
      statusEl.textContent = replaceNext(activeTarget.view) ? '置換しました' : '置換対象が見つかりません'
      return
    }

    if (activeTarget?.type === 'document') {
      const replaced = replaceInDocument(activeTarget.controller)
      statusEl.textContent = replaced ? '置換しました' : '置換対象が見つかりません'
    }
  }

  function runReplaceAll() {
    if (!searchInput.value) {
      statusEl.textContent = '検索文字列を入力してください'
      return
    }

    if (activeTarget?.type === 'codemirror') {
      if (!applyQuery(activeTarget.view, searchInput.value, replaceInput.value, caseInput.checked)) return
      const count = replaceAll(activeTarget.view)
      statusEl.textContent = count ? `${count} 件置換しました` : '一致するものが見つかりません'
      return
    }

    if (activeTarget?.type === 'document') {
      const controller = activeTarget.controller
      const { source, count } = replaceAllInDocument(
        controller.getDocument(),
        searchInput.value,
        replaceInput.value,
        caseInput.checked,
      )
      if (!count) {
        statusEl.textContent = '一致するものが見つかりません'
        return
      }
      controller.applyDocument(source)
      documentMatchIndex = -1
      statusEl.textContent = `${count} 件置換しました`
    }
  }

  return dialogEl
}

/**
 * @param {import('@codemirror/view').EditorView} view
 * @param {{ x?: number, y?: number, initialSearch?: string }} [options]
 */
export function openSearchReplaceDialog(view, { x, y, initialSearch } = {}) {
  openDialog({
    type: 'codemirror',
    view,
    initialSearch: initialSearch ?? getSelectedTextFromView(view),
    x,
    y,
    scopeLabel: '',
  })
}

/**
 * @param {DocumentSearchController} controller
 * @param {{ x?: number, y?: number, initialSearch?: string }} [options]
 */
export function openDocumentSearchReplaceDialog(controller, { x, y, initialSearch } = {}) {
  openDialog({
    type: 'document',
    controller,
    initialSearch: initialSearch ?? controller.getSelectedText(),
    x,
    y,
    scopeLabel: 'WYSIWYG 全文',
  })
}

/**
 * @param {{
 *   type: 'codemirror'
 *   view: import('@codemirror/view').EditorView
 *   initialSearch?: string
 *   x?: number
 *   y?: number
 *   scopeLabel?: string
 * } | {
 *   type: 'document'
 *   controller: DocumentSearchController
 *   initialSearch?: string
 *   x?: number
 *   y?: number
 *   scopeLabel?: string
 * }} config
 */
function openDialog(config) {
  createSearchReplaceDialog()
  if (!dialogEl) return

  documentMatchIndex = -1

  if (config.type === 'codemirror') {
    activeTarget = { type: 'codemirror', view: config.view }
    config.view.focus()
    applyQuery(config.view, config.initialSearch ?? '', '', false)
  } else {
    activeTarget = { type: 'document', controller: config.controller }
  }

  const searchInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.search-input'))
  const replaceInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.replace-input'))
  const caseInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.case-sensitive-input'))
  const statusEl = /** @type {HTMLElement} */ (dialogEl.querySelector('.search-replace-status'))
  const scopeEl = /** @type {HTMLElement} */ (dialogEl.querySelector('.search-replace-scope'))

  searchInput.value = config.initialSearch ?? ''
  replaceInput.value = ''
  caseInput.checked = false
  statusEl.textContent = ''
  scopeEl.textContent = config.scopeLabel ?? ''

  dialogEl.hidden = false

  if (typeof config.x === 'number' && typeof config.y === 'number') {
    positionDialog(config.x, config.y)
  } else {
    dialogEl.style.left = '50%'
    dialogEl.style.top = '20%'
    dialogEl.style.transform = 'translateX(-50%)'
  }

  searchInput.focus()
  searchInput.select()
}

export function closeSearchReplaceDialog() {
  if (dialogEl) {
    dialogEl.hidden = true
  }
  activeTarget = null
  documentMatchIndex = -1
}

/**
 * @param {DocumentSearchController} controller
 * @param {boolean} reverse
 */
function findInDocument(controller, reverse) {
  const searchInput = /** @type {HTMLInputElement} */ (dialogEl?.querySelector('.search-input'))
  const caseInput = /** @type {HTMLInputElement} */ (dialogEl?.querySelector('.case-sensitive-input'))
  if (!searchInput) return false

  const source = controller.getDocument()
  const matches = findDocumentMatches(source, searchInput.value, caseInput.checked)
  if (matches.length === 0) return false

  const cursor = controller.getCursorPosition()
  const current = documentMatchIndex >= 0 ? matches[documentMatchIndex] : null
  const afterCurrent = current && cursor >= current.from && cursor <= current.to

  if (reverse) {
    if (afterCurrent) {
      documentMatchIndex = pickNextDocumentMatch(matches, current.from, true)
    } else {
      documentMatchIndex = pickNextDocumentMatch(matches, cursor, true)
    }
  } else if (afterCurrent) {
    documentMatchIndex = pickNextDocumentMatch(matches, current.to, false)
  } else {
    documentMatchIndex = pickNextDocumentMatch(matches, cursor, false)
  }

  const match = matches[documentMatchIndex]
  controller.revealMatch(match.from, match.to)
  return true
}

/**
 * @param {DocumentSearchController} controller
 */
function replaceInDocument(controller) {
  const searchInput = /** @type {HTMLInputElement} */ (dialogEl?.querySelector('.search-input'))
  const replaceInput = /** @type {HTMLInputElement} */ (dialogEl?.querySelector('.replace-input'))
  const caseInput = /** @type {HTMLInputElement} */ (dialogEl?.querySelector('.case-sensitive-input'))
  if (!searchInput) return false

  const source = controller.getDocument()
  const matches = findDocumentMatches(source, searchInput.value, caseInput.checked)
  if (matches.length === 0) return false

  if (documentMatchIndex < 0) {
    documentMatchIndex = pickNextDocumentMatch(matches, controller.getCursorPosition(), false)
  }

  const match = matches[documentMatchIndex]
  const nextSource = replaceDocumentMatch(source, match, replaceInput.value)
  controller.applyDocument(nextSource)

  const nextMatches = findDocumentMatches(nextSource, searchInput.value, caseInput.checked)
  if (nextMatches.length === 0) {
    documentMatchIndex = -1
    return true
  }

  documentMatchIndex = Math.min(documentMatchIndex, nextMatches.length - 1)
  const nextMatch = nextMatches[documentMatchIndex]
  controller.revealMatch(nextMatch.from, nextMatch.to)
  return true
}

/**
 * @param {DocumentSearchController} controller
 */
function formatDocumentMatchStatus(controller) {
  const searchInput = /** @type {HTMLInputElement} */ (dialogEl?.querySelector('.search-input'))
  const caseInput = /** @type {HTMLInputElement} */ (dialogEl?.querySelector('.case-sensitive-input'))
  if (!searchInput || documentMatchIndex < 0) return ''

  const matches = findDocumentMatches(
    controller.getDocument(),
    searchInput.value,
    caseInput.checked,
  )
  if (matches.length === 0) return ''
  return `${documentMatchIndex + 1} / ${matches.length}`
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
function getSelectedTextFromView(view) {
  const { from, to } = view.state.selection.main
  return from !== to ? view.state.sliceDoc(from, to) : ''
}

/**
 * @param {import('@codemirror/view').EditorView} view
 * @param {string} search
 * @param {string} replace
 * @param {boolean} caseSensitive
 */
function applyQuery(view, search, replace, caseSensitive) {
  if (!search) return false
  view.dispatch({
    effects: setSearchQuery.of(
      new SearchQuery({
        search,
        replace,
        caseSensitive,
      }),
    ),
  })
  return true
}

/**
 * @param {number} x
 * @param {number} y
 */
function positionDialog(x, y) {
  if (!dialogEl) return

  dialogEl.style.transform = 'none'
  const margin = 8
  const rect = dialogEl.getBoundingClientRect()
  let left = x
  let top = y

  if (left + rect.width > window.innerWidth - margin) {
    left = window.innerWidth - rect.width - margin
  }
  if (top + rect.height > window.innerHeight - margin) {
    top = window.innerHeight - rect.height - margin
  }

  dialogEl.style.left = `${Math.max(margin, left)}px`
  dialogEl.style.top = `${Math.max(margin, top)}px`
}
