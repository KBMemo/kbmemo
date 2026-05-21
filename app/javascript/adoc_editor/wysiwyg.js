import { asciidocBlockToHtml } from './asciidoc/blockConvert.js'
import { htmlToAsciidoc, unitToAsciidoc } from './asciidoc/htmlToAsciidoc.js'
import {
  getActiveUnitIndex,
  getCaretOffsetInUnit,
  parseEditUnitsFromSource,
  shouldSplitEditUnits,
} from './asciidoc/parseEditUnits.js'
import { refreshPreview } from './asciidoc/parseSession.js'
import { renderPreviewHtml } from './preview.js'
import {
  createWysiwygSourceEditor,
  destroyWysiwygSourceEditor,
  focusWysiwygSourceEditor,
  getWysiwygSourceSelection,
  getWysiwygSourceValue,
  getWysiwygSourceView,
  setWysiwygSourceSelection,
  setWysiwygSourceRange,
  isWysiwygSourceComposing,
} from './wysiwygSourceEditor.js'
import { flattenAndWrapUnits } from './wysiwygUnits.js'
import { openEditorContextMenu } from './editorContextMenu.js'
import {
  buildSourceSegments,
  findChangeCursorPosition,
  findSegmentForOffset,
  findSegmentIndexForOffset,
  normalizeDocumentSource,
} from './wysiwygDocumentSearch.js'
import { openDocumentSearchReplaceDialog } from './searchReplaceDialog.js'
import { isModF } from './searchKeybindings.js'
import { createWysiwygHistory, isModRedo, isModZ } from './wysiwygHistory.js'

const SPLIT_DEBOUNCE_MS = 300
const SYNC_DEBOUNCE_MS = 400

/**
 * @param {HTMLElement} editorEl
 * @param {HTMLElement} toolbarEl
 * @param {{ onSourceChange: (source: string) => void, paneEl?: HTMLElement | null, getMemoId?: () => string | null | undefined }} options
 */
export function createWysiwygEditor(editorEl, toolbarEl, { onSourceChange, paneEl, getMemoId }) {
  let syncTimer
  let splitTimer
  let isRendering = false
  let isSwitchingUnit = false
  /** @type {HTMLElement | null} */
  let activeSourceUnit = null
  const history = createWysiwygHistory()
  let isApplyingHistory = false

  toolbarEl.addEventListener('click', (event) => {
    const button = event.target.closest('[data-cmd]')
    if (!button) return
    event.preventDefault()
    if (activeSourceUnit) return
    applyCommand(editorEl, button.getAttribute('data-cmd'), button.getAttribute('data-value'))
    wrapUnits(editorEl)
    scheduleSync()
  })

  editorEl.addEventListener('paste', (event) => {
    if (event.target instanceof HTMLElement && event.target.closest('.wysiwyg-source-editor')) return
    if (activeSourceUnit) {
      event.preventDefault()
    }
  })

  editorEl.addEventListener('contextmenu', (event) => {
    void openWysiwygContextMenu(event)
  }, { capture: true })

  const wysiwygViewEl = paneEl ?? editorEl.closest('.memo-body-editor__wysiwyg-pane')
  wysiwygViewEl?.addEventListener('keydown', (event) => {
    if (event.target instanceof HTMLElement && event.target.closest('.wysiwyg-source-editor')) return
    if (event.target instanceof HTMLElement && event.target.closest('.search-replace-dialog')) return

    if (isModF(event)) {
      event.preventDefault()
      openDocumentSearch()
      return
    }

    if (isModZ(event)) {
      event.preventDefault()
      undoDocument()
      return
    }

    if (isModRedo(event)) {
      event.preventDefault()
      redoDocument()
    }
  })

  function getDocumentSource() {
    return htmlToAsciidoc(editorEl, { getSourceValue: getWysiwygSourceValue })
  }

  function rebuildSourceReplacingSegment(source, segmentIndex, newText) {
    const segments = buildSourceSegments(source)
    if (segmentIndex < 0 || segmentIndex >= segments.length) {
      return normalizeDocumentSource(source)
    }

    const updated = segments.map((segment, index) =>
      index === segmentIndex ? { ...segment, text: newText } : segment,
    )
    return normalizeDocumentSource(updated.map((segment) => segment.text).join('\n\n'))
  }

  function getActiveSegmentIndex() {
    if (!activeSourceUnit) return -1

    const sourceSegments = buildSourceSegments(normalizeDocumentSource(history.getCurrent()))
    const { segments: domSegments } = collectDocumentSegments()
    const domIndex = domSegments.findIndex((entry) => entry.unit === activeSourceUnit)
    if (domIndex === -1) return -1

    if (domIndex < sourceSegments.length) return domIndex

    const domSegment = domSegments[domIndex]
    return sourceSegments.findIndex((entry) => entry.text === domSegment.text)
  }

  function getDocumentSourceForSync() {
    if (!activeSourceUnit) return getDocumentSource()

    const host = activeSourceUnit.querySelector(':scope > .wysiwyg-source-editor')
    if (!(host instanceof HTMLElement)) return getDocumentSource()

    const segmentIndex = getActiveSegmentIndex()
    if (segmentIndex < 0) return getDocumentSource()

    return rebuildSourceReplacingSegment(
      history.getCurrent(),
      segmentIndex,
      getWysiwygSourceValue(host).trim(),
    )
  }

  function getCursorPositionForSync(next) {
    if (!activeSourceUnit) return getGlobalCursorPosition()

    const host = activeSourceUnit.querySelector(':scope > .wysiwyg-source-editor')
    if (!(host instanceof HTMLElement)) return getGlobalCursorPosition()

    const segmentIndex = getActiveSegmentIndex()
    const segments = buildSourceSegments(next)
    const segment = segments[segmentIndex]
    if (!segment) return getGlobalCursorPosition()

    return segment.from + getWysiwygSourceSelection(host)
  }

  function flushSyncNow() {
    clearTimeout(syncTimer)
    clearTimeout(splitTimer)
    syncFromDom()
  }

  function commitHistoryChange(next, cursor = getGlobalCursorPosition()) {
    const previous = history.getCurrentEntry()
    const normalizedNext = normalizeDocumentSource(next)
    const normalizedPrevious = normalizeDocumentSource(previous.source)
    const undoCursor = findChangeCursorPosition(normalizedPrevious, normalizedNext, previous.cursor)
    return history.commit(normalizedNext, cursor, undoCursor)
  }

  function applyHistorySource(source, restoreCursor) {
    clearTimeout(syncTimer)
    clearTimeout(splitTimer)
    const normalizedSource = normalizeDocumentSource(source)
    history.setCurrent(normalizedSource, restoreCursor ?? 0)
    onSourceChange(normalizedSource)
    isApplyingHistory = true
    renderFromSourceInternal(normalizedSource)
    revealDocumentOffset(normalizedSource, restoreCursor ?? 0)
    isApplyingHistory = false
  }

  function commitDocumentSource(source, { restoreCursor } = {}) {
    flushSyncNow()
    const cursor = restoreCursor ?? getGlobalCursorPosition()
    commitHistoryChange(source, cursor)
    applyHistorySource(source, cursor)
  }

  function undoDocument() {
    if (!history.canUndo()) return false

    flushSyncNow()
    if (!history.canUndo()) return false

    const currentCursor = getGlobalCursorPosition()
    const entry = history.undo(currentCursor)
    if (entry === null) return false
    applyHistorySource(entry.source, entry.cursor)
    return true
  }

  function redoDocument() {
    if (!history.canRedo()) return false

    flushSyncNow()
    if (!history.canRedo()) return false

    const currentCursor = getGlobalCursorPosition()
    const entry = history.redo(currentCursor)
    if (entry === null) return false
    applyHistorySource(entry.source, entry.cursor)
    return true
  }

  function createDocumentHistoryController() {
    return {
      canUndo: () => history.canUndo(),
      canRedo: () => history.canRedo(),
      undo: () => undoDocument(),
      redo: () => redoDocument(),
    }
  }

  function openDocumentSearch() {
    openDocumentSearchReplaceDialog(createDocumentSearchController())
  }

  function openWysiwygContextMenu(event, getView = getActiveSourceView) {
    return openEditorContextMenu(event, {
      scope: 'wysiwyg',
      getView,
      getDocumentSearchController: createDocumentSearchController,
      getDocumentHistoryController: createDocumentHistoryController,
      onBeforeEdit: (contextEvent) => {
        ensureSourceEditable(contextEvent)
      },
    })
  }

  function collectDocumentSegments() {
    /** @type {{ unit: HTMLElement, text: string, from: number, to: number }[]} */
    const segments = []
    let offset = 0

    for (const unit of editorEl.querySelectorAll(':scope > .wysiwyg-unit')) {
      let text = ''
      if (unit.classList.contains('is-source')) {
        const host = unit.querySelector(':scope > .wysiwyg-source-editor')
        if (host instanceof HTMLElement) {
          text = getWysiwygSourceValue(host)
        }
      } else {
        text = unitToAsciidoc(unit)
      }

      text = text.trim()
      if (!text) continue

      const from = offset
      const to = offset + text.length
      segments.push({ unit: /** @type {HTMLElement} */ (unit), text, from, to })
      offset = to + 2
    }

    const fullSource = segments.map((segment) => segment.text).join('\n\n') + (segments.length ? '\n' : '')
    return { segments, fullSource }
  }

  function getGlobalCursorPosition() {
    const source = activeSourceUnit
      ? getDocumentSourceForSync()
      : normalizeDocumentSource(getDocumentSource())
    const sourceSegments = buildSourceSegments(source)
    if (!activeSourceUnit || sourceSegments.length === 0) return 0

    const host = activeSourceUnit.querySelector(':scope > .wysiwyg-source-editor')
    const segmentIndex = getActiveSegmentIndex()
    const sourceSegment = segmentIndex >= 0 ? sourceSegments[segmentIndex] : null
    if (!sourceSegment) return 0

    if (!(host instanceof HTMLElement)) return sourceSegment.from

    return sourceSegment.from + getWysiwygSourceSelection(host)
  }

  function revealDocumentOffset(source, offset, { skipSync = true } = {}) {
    const sourceSegments = buildSourceSegments(source)
    if (sourceSegments.length === 0) return

    const maxOffset = source.trimEnd().length
    const clamped = Math.max(0, Math.min(offset, maxOffset))
    const segmentIndex = findSegmentIndexForOffset(sourceSegments, clamped)
    const sourceSegment = sourceSegments[segmentIndex]
    const { segments: domSegments } = collectDocumentSegments()
    const segment =
      domSegments[segmentIndex]?.text === sourceSegment.text
        ? domSegments[segmentIndex]
        : domSegments.find((entry) => entry.text === sourceSegment.text) ??
          findSegmentForOffset(domSegments, clamped)

    if (!segment) return

    const localFrom = Math.max(0, Math.min(clamped - sourceSegment.from, sourceSegment.text.length))
    activateSourceUnit(segment.unit, {
      caret: localFrom,
      source: segment.text,
      skipSync,
    })
    clearStraySelection(segment.unit)
  }

  function clearStraySelection(keepUnit) {
    const selection = window.getSelection()
    if (!selection || selection.rangeCount === 0) return

    const anchor = selection.anchorNode
    if (anchor && keepUnit.contains(anchor)) return
    if (anchor?.parentElement && keepUnit.contains(anchor.parentElement)) return

    selection.removeAllRanges()
  }

  function revealDocumentMatch(from, to) {
    const source = getDocumentSource()
    revealDocumentOffset(source, from)

    if (from === to || !activeSourceUnit) return

    const host = activeSourceUnit.querySelector(':scope > .wysiwyg-source-editor')
    if (!(host instanceof HTMLElement)) return

    const { segments } = collectDocumentSegments()
    const segment = findSegmentForOffset(segments, from)
    if (!segment) return

    const localFrom = Math.max(0, from - segment.from)
    const localTo = Math.max(localFrom, Math.min(to, segment.to) - segment.from)
    focusWysiwygSourceEditor(host)
    setWysiwygSourceRange(host, localFrom, localTo)
  }

  function createDocumentSearchController() {
    return {
      getDocument() {
        return collectDocumentSegments().fullSource
      },
      getCursorPosition() {
        return getGlobalCursorPosition()
      },
      getSelectedText() {
        const host = activeSourceUnit?.querySelector(':scope > .wysiwyg-source-editor')
        if (host instanceof HTMLElement) {
          const view = getWysiwygSourceView(host)
          if (view) {
            const { from, to } = view.state.selection.main
            if (from !== to) return view.state.sliceDoc(from, to)
          }
        }
        return window.getSelection()?.toString() ?? ''
      },
      applyDocument(source) {
        commitDocumentSource(source, { restoreCursor: getGlobalCursorPosition() })
      },
      revealMatch(from, to) {
        revealDocumentMatch(from, to)
      },
    }
  }

  function getActiveSourceView() {
    const host = activeSourceUnit?.querySelector(':scope > .wysiwyg-source-editor')
    if (host instanceof HTMLElement) {
      return getWysiwygSourceView(host)
    }
    return null
  }

  function ensureSourceEditable(event) {
    const target = event.target instanceof HTMLElement ? event.target : null
    if (!target || target.closest('.wysiwyg-source-editor')) return

    const unit = target.closest('.wysiwyg-unit')
    if (!unit || !editorEl.contains(unit)) return
    if (unit === activeSourceUnit) return

    activateSourceUnit(/** @type {HTMLElement} */ (unit))
  }

  editorEl.addEventListener('mousedown', (event) => {
    if (event.button !== 0) return
    if (isRendering || isSwitchingUnit) return
    const target = /** @type {HTMLElement} */ (event.target)
    if (target.closest('.wysiwyg-source-editor')) return

    const unit = target.closest('.wysiwyg-unit')
    if (!unit || !editorEl.contains(unit)) return
    if (unit === activeSourceUnit) return

    event.preventDefault()
    activateSourceUnit(/** @type {HTMLElement} */ (unit))
  })

  document.addEventListener('selectionchange', () => {
    if (isRendering || isSwitchingUnit || isApplyingHistory) return
    if (!editorEl.isConnected) return

    const selection = window.getSelection()
    if (!selection || selection.rangeCount === 0) return

    const anchor = selection.anchorNode
    if (!anchor || !editorEl.contains(anchor)) return
    if (anchor instanceof HTMLElement && anchor.closest('.wysiwyg-source-editor')) return
    if (anchor.parentElement?.closest('.wysiwyg-source-editor')) return

    const unit = getUnitFromNode(anchor)
    if (!unit || unit === activeSourceUnit) return

    activateSourceUnit(unit)
  })

  function isActiveUnitComposing() {
    const host = activeSourceUnit?.querySelector(':scope > .wysiwyg-source-editor')
    return host instanceof HTMLElement && isWysiwygSourceComposing(host)
  }

  function scheduleSync() {
    if (isActiveUnitComposing()) return
    clearTimeout(syncTimer)
    syncTimer = setTimeout(syncFromDom, SYNC_DEBOUNCE_MS)
  }

  function scheduleSplitCheck(host) {
    if (isWysiwygSourceComposing(host)) return
    clearTimeout(splitTimer)
    splitTimer = setTimeout(() => trySplitActiveUnit(host), SPLIT_DEBOUNCE_MS)
  }

  function syncFromDom() {
    if (isApplyingHistory || isRendering || isActiveUnitComposing()) return
    const next = getDocumentSourceForSync()
    const cursor = getCursorPositionForSync(next)
    if (commitHistoryChange(next, cursor)) {
      onSourceChange(next)
    }
  }

  function renderFromSourceInternal(source) {
    isRendering = true
    activeSourceUnit = null
    const memoId = getMemoId?.()
    const { html } = refreshPreview(source, { memoId })
    renderPreviewHtml(html, editorEl, memoId)
    wrapUnits(editorEl, { skipDeactivate: true })
    isRendering = false
  }

  function renderFromSource(source) {
    clearTimeout(syncTimer)
    clearTimeout(splitTimer)
    if (activeSourceUnit) {
      deactivateSourceUnit(activeSourceUnit)
    }
    history.reset(normalizeDocumentSource(source))
    isApplyingHistory = true
    renderFromSourceInternal(source)
    isApplyingHistory = false
  }

  function flush() {
    clearTimeout(syncTimer)
    clearTimeout(splitTimer)
    if (activeSourceUnit) {
      deactivateSourceUnit(activeSourceUnit)
    }
    syncFromDom()
  }

  /**
   * @param {HTMLElement} unit
   * @param {{ caret?: 'start' | 'end' | number, caretEnd?: number, source?: string, skipSync?: boolean }} [options]
   */
  function activateSourceUnit(unit, { caret = 'start', caretEnd, source, skipSync = false } = {}) {
    if (activeSourceUnit === unit) {
      const host = unit.querySelector(':scope > .wysiwyg-source-editor')
      if (host instanceof HTMLElement && (caretEnd !== undefined || typeof caret === 'number')) {
        const from =
          caret === 'end'
            ? getWysiwygSourceValue(host).length
            : caret === 'start'
              ? 0
              : caret
        const to = caretEnd ?? from
        focusWysiwygSourceEditor(host)
        setWysiwygSourceRange(host, from, to)
      }
      return
    }

    isSwitchingUnit = true
    if (activeSourceUnit) {
      deactivateSourceUnit(activeSourceUnit)
    }
    removeEmptyRenderedUnits(new Set([unit]))

    const initialSource = source ?? unitToAsciidoc(unit).trim()
    unit.replaceChildren()
    unit.classList.add('is-source')
    unit.contentEditable = 'false'

    const host = createSourceEditorHost(initialSource, {
      onChange: () => {
        scheduleSplitCheck(host)
        scheduleSync()
      },
      onKeyDown: (event, view) => handleSourceKeydown(event, view, activateSourceUnit),
      onContextMenu: (event, view) => {
        void openWysiwygContextMenu(event, () => view)
      },
      onModF: () => openDocumentSearch(),
      onUndo: () => undoDocument(),
      onRedo: () => redoDocument(),
    })
    unit.append(host)

    activeSourceUnit = unit

    const position =
      caret === 'end'
        ? initialSource.length
        : caret === 'start'
          ? 0
          : caret
    if (caretEnd !== undefined) {
      setWysiwygSourceRange(host, position, caretEnd)
    } else {
      setWysiwygSourceSelection(host, position)
    }
    focusWysiwygSourceEditor(host)
    isSwitchingUnit = false
  }

  /**
   * @param {HTMLElement} unit
   */
  function deactivateSourceUnit(unit) {
    const host = unit.querySelector(':scope > .wysiwyg-source-editor')
    if (!(host instanceof HTMLElement)) return

    const adoc = getWysiwygSourceValue(host)
    destroyWysiwygSourceEditor(host)

    if (!adoc.trim()) {
      removeEmptyUnit(unit)
      return
    }

    const temp = document.createElement('div')
    renderPreviewHtml(asciidocBlockToHtml(adoc), temp, getMemoId?.())

    unit.classList.remove('is-source')
    unit.contentEditable = 'false'
    unit.replaceChildren(...temp.childNodes)

    if (activeSourceUnit === unit) {
      activeSourceUnit = null
    }
  }

  /**
   * @param {HTMLElement} unit
   */
  function removeEmptyUnit(unit) {
    const host = unit.querySelector(':scope > .wysiwyg-source-editor')
    if (host instanceof HTMLElement) {
      destroyWysiwygSourceEditor(host)
    }
    if (activeSourceUnit === unit) {
      activeSourceUnit = null
    }
    unit.remove()
  }

  /**
   * @param {Set<HTMLElement>} keep
   */
  function removeEmptyRenderedUnits(keep) {
    for (const unit of [...editorEl.querySelectorAll(':scope > .wysiwyg-unit')]) {
      if (keep.has(unit)) continue
      if (unit.classList.contains('is-source')) continue
      if (!unitToAsciidoc(unit).trim()) {
        unit.remove()
      }
    }
  }

  /**
   * @param {HTMLElement} host
   */
  function trySplitActiveUnit(host) {
    if (isSwitchingUnit || isRendering) return
    if (activeSourceUnit !== host.closest('.wysiwyg-unit')) return

    const source = getWysiwygSourceValue(host)
    if (!shouldSplitEditUnits(source)) return

    const parsedUnits = parseEditUnitsFromSource(source)
    const selectionStart = getWysiwygSourceSelection(host)
    const cursorLine = source.slice(0, selectionStart).split('\n').length - 1
    const activeIndex = getActiveUnitIndex(parsedUnits, cursorLine)
    const activeUnit = parsedUnits[activeIndex]
    const caret = getCaretOffsetInUnit(source, activeUnit, selectionStart)

    isSwitchingUnit = true
    clearTimeout(splitTimer)

    destroyWysiwygSourceEditor(host)

    const currentUnit = /** @type {HTMLElement} */ (activeSourceUnit)
    const newElements = parsedUnits.map((unitData, index) => buildUnitElement(unitData.adoc, index === activeIndex))

    currentUnit.replaceWith(...newElements)
    activeSourceUnit = newElements[activeIndex]

    const nextHost = activeSourceUnit.querySelector('.wysiwyg-source-editor')
    if (nextHost instanceof HTMLElement) {
      focusWysiwygSourceEditor(nextHost)
      setWysiwygSourceSelection(nextHost, caret)
    }

    isSwitchingUnit = false
    scheduleSync()
  }

  /**
   * @param {string} adoc
   * @param {boolean} asSource
   */
  function buildUnitElement(adoc, asSource) {
    const wrapper = document.createElement('div')
    wrapper.className = 'wysiwyg-unit'
    wrapper.contentEditable = 'false'

    if (asSource) {
      wrapper.classList.add('is-source')
      wrapper.append(
        createSourceEditorHost(adoc, {
          onChange: () => {
            const host = wrapper.querySelector('.wysiwyg-source-editor')
            if (host instanceof HTMLElement) {
              scheduleSplitCheck(host)
            }
            scheduleSync()
          },
          onKeyDown: (event, view) => handleSourceKeydown(event, view, activateSourceUnit),
          onContextMenu: (event, view) => {
            void openWysiwygContextMenu(event, () => view)
          },
          onModF: () => openDocumentSearch(),
          onUndo: () => undoDocument(),
          onRedo: () => redoDocument(),
        }),
      )
      return wrapper
    }

    const temp = document.createElement('div')
    renderPreviewHtml(asciidocBlockToHtml(adoc), temp, getMemoId?.())
    wrapper.append(...temp.childNodes)
    return wrapper
  }

  function wrapUnits(container = editorEl, { skipDeactivate = false } = {}) {
    if (!skipDeactivate && activeSourceUnit) {
      deactivateSourceUnit(activeSourceUnit)
    }
    flattenAndWrapUnits(container)
  }

  return {
    renderFromSource,
    flush,
    wrapUnits,
    getActiveSourceView,
    ensureSourceEditable,
    createDocumentSearchController,
    focus() {
      const firstUnit = editorEl.querySelector(':scope > .wysiwyg-unit')
      if (firstUnit instanceof HTMLElement) {
        activateSourceUnit(firstUnit)
        return
      }
      editorEl.focus()
    },
  }
}

/**
 * @param {string} source
 * @param {{ onChange: () => void, onKeyDown: (event: KeyboardEvent, view: import('@codemirror/view').EditorView) => boolean | void, onContextMenu?: (event: MouseEvent, view: import('@codemirror/view').EditorView) => void }} handlers
 */
function createSourceEditorHost(source, { onChange, onKeyDown, onContextMenu, onModF, onUndo, onRedo }) {
  return createWysiwygSourceEditor(source, {
    onChange: () => onChange(),
    onKeyDown,
    onContextMenu,
    onModF,
    onUndo,
    onRedo,
  })
}

/**
 * @param {Node | null} node
 * @returns {HTMLElement | null}
 */
function getUnitFromNode(node) {
  if (!node) return null
  const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement
  return element?.closest('.wysiwyg-unit') ?? null
}

/**
 * @param {KeyboardEvent} event
 * @param {import('@codemirror/view').EditorView} view
 * @param {(unit: HTMLElement, options?: { caret?: 'start' | 'end' | number, source?: string }) => void} activateSourceUnit
 */
function handleSourceKeydown(event, view, activateSourceUnit) {
  const host = view.dom
  const unit = host.closest('.wysiwyg-unit')
  if (!(unit instanceof HTMLElement)) return false

  if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
    const selection = view.state.selection.main
    if (selection.from !== selection.to) return false

    const value = view.state.doc.toString()
    const lineIndex = value.slice(0, selection.head).split('\n').length - 1
    const lineCount = value ? value.split('\n').length : 1
    const atTopLine = lineIndex === 0
    const atBottomLine = lineIndex === lineCount - 1

    if (event.key === 'ArrowUp' && !atTopLine) return false
    if (event.key === 'ArrowDown' && !atBottomLine) return false

    const editorEl = unit.parentElement
    if (!editorEl) return false

    const units = [...editorEl.querySelectorAll(':scope > .wysiwyg-unit')]
    const index = units.indexOf(unit)
    const nextIndex = event.key === 'ArrowUp' ? index - 1 : index + 1
    const nextUnit = units[nextIndex]
    if (!(nextUnit instanceof HTMLElement)) return false

    event.preventDefault()
    activateSourceUnit(nextUnit, { caret: event.key === 'ArrowUp' ? 'end' : 'start' })
    return true
  }

  if (event.key !== 'Tab') return false

  event.preventDefault()
  const spaces = '  '
  view.dispatch(view.state.replaceSelection(spaces))
  return true
}

/**
 * @param {HTMLElement} editorEl
 * @param {string | null} cmd
 * @param {string | null} value
 */
function applyCommand(editorEl, cmd, value) {
  editorEl.focus()

  switch (cmd) {
    case 'bold':
      document.execCommand('bold')
      break
    case 'italic':
      document.execCommand('italic')
      break
    case 'code':
      document.execCommand('insertHTML', false, `<code>${escapeHtml(getSelectionText() || 'code')}</code>`)
      break
    case 'h1':
    case 'h2':
    case 'h3':
      document.execCommand('formatBlock', false, value ?? cmd.toUpperCase())
      break
    case 'ul':
      document.execCommand('insertUnorderedList')
      break
    case 'ol':
      document.execCommand('insertOrderedList')
      break
    case 'paragraph':
      document.execCommand('formatBlock', false, 'P')
      break
    case 'link': {
      const url = window.prompt('URL')
      if (url) document.execCommand('createLink', false, url)
      break
    }
    default:
      break
  }
}

function getSelectionText() {
  return window.getSelection()?.toString() ?? ''
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
