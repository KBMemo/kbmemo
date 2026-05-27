import {
  asciidocBlockToHtml,
  unitToAsciidoc,
  isIndentLiteralBlock,
  INDENT_LITERAL_DATA_ATTR,
  normalizeBlockSegmentText,
  getActiveUnitIndex,
  getCaretOffsetInUnit,
  getCaretInFollowingBlock,
  getTableParagraphSplit,
  parseEditUnitsFromSource,
  shouldSplitEditUnits,
  splitIndentLiteralAtBlankLine,
  splitParagraphAtBlankLine,
} from '@kbmemo/adoc-codemirror'
import {
  getScrollRoot,
  normalizeMemoImagePathsInSource,
  substituteDiagramsForPreview,
  ensureWikiLinkLabelsInCache,
  extractWikiLinkTargets,
  substituteWikiLinksForPreview,
  literalParagraphContinuationExtension,
} from '@kbmemo/adoc-kbmemo'
import { renderPreviewHtml } from '@kbmemo/adoc-preview'
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
import {
  getUnitAdocSource,
  hasUnitAdocSource,
  setUnitAdocSource,
} from './wysiwyg_unit_source.js'
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
import { createWysiwygSourceExtensions } from './wysiwygSourceExtensions.js'
import {
  createWebPasteHandler,
  insertTextIntoEditorView,
} from './webPaste.js'

const SPLIT_DEBOUNCE_MS = 300
const SYNC_DEBOUNCE_MS = 400

/**
 * @param {HTMLElement} editorEl
 * @param {{ onSourceChange: (source: string) => void, paneEl?: HTMLElement | null, getMemoId?: () => string | null | undefined, getWikiConfig?: () => { completionsUrl?: string, labelsUrl?: string, memoId?: string | null }, sourceExtensions?: import('@codemirror/state').Extension[] }} options
 */
export function createWysiwygEditor(editorEl, { onSourceChange, paneEl, getMemoId, getWikiConfig, sourceExtensions = [] }) {
  let syncTimer
  let splitTimer
  let isRendering = false
  let isSwitchingUnit = false
  /** @type {HTMLElement | null} */
  let activeSourceUnit = null
  const history = createWysiwygHistory()
  let isApplyingHistory = false
  /** @type {(view: import('@codemirror/view').EditorView) => void} */
  let splitUnitOnBlankLineFromView = () => {}
  const wikiExtensions = createWysiwygSourceExtensions({
    sourceExtensions: [
      ...sourceExtensions,
      literalParagraphContinuationExtension({
        onSplitToParagraph: (view) => splitUnitOnBlankLineFromView(view),
      }),
    ],
    getWikiConfig,
  })
  /** @type {Map<string, object>} */
  const wikiLabelCache = new Map()
  let wikiLabelRefreshSeq = 0
  const webPasteHandler = createWebPasteHandler({
    insertText(text, view) {
      if (view) {
        insertTextIntoEditorView(view, text)
        const host = view.dom.closest('.wysiwyg-source-editor')
        const unit = host?.closest('.wysiwyg-unit')
        if (host instanceof HTMLElement && unit instanceof HTMLElement) {
          setUnitAdocSource(unit, getWysiwygSourceValue(host))
          scheduleSync()
        }
        return
      }
      insertTextAtSelection(text)
    },
  })

  function previewHtmlForAdoc(adoc) {
    let processed = substituteDiagramsForPreview(adoc)
    processed = substituteWikiLinksForPreview(processed, wikiLabelCache)
    return asciidocBlockToHtml(processed, getMemoId?.())
  }

  /**
   * @param {HTMLElement} unit
   * @param {string} adoc
   */
  function renderUnitPreview(unit, adoc) {
    const temp = document.createElement('div')
    renderPreviewHtml(previewHtmlForAdoc(adoc), temp, getMemoId?.())
    if (isIndentLiteralBlock(adoc)) {
      for (const block of temp.querySelectorAll('.literalblock')) {
        block.dataset[INDENT_LITERAL_DATA_ATTR] = 'true'
      }
    }
    annotateParagraphHardbreaks(adoc, temp)
    unit.replaceChildren(...temp.childNodes)
  }

  /**
   * @param {string} adoc
   * @param {ParentNode} previewRoot
   */
  function annotateParagraphHardbreaks(adoc, previewRoot) {
    const trimmed = adoc.trimStart()
    if (trimmed.startsWith('[%hardbreaks]')) {
      for (const block of previewRoot.querySelectorAll('.paragraph')) {
        block.dataset.kbHardbreaks = 'true'
      }
    }
  }

  async function refreshWikiLabelPreviews(source) {
    const config = getWikiConfig?.()
    if (!config?.labelsUrl) return

    await ensureWikiLinkLabelsInCache(
      wikiLabelCache,
      config.labelsUrl,
      config.memoId ?? null,
      source,
    )

    const seq = ++wikiLabelRefreshSeq
    for (const unit of editorEl.querySelectorAll(':scope > .wysiwyg-unit')) {
      if (seq !== wikiLabelRefreshSeq) return
      if (unit.classList.contains('is-source')) continue

      const adoc = getUnitAdocSource(unit)
      if (adoc === undefined) continue
      if (!extractWikiLinkTargets(adoc).some((target) => wikiLabelCache.has(target))) continue

      renderUnitPreview(/** @type {HTMLElement} */ (unit), adoc)
    }
  }

  async function ensureDocumentWikiLabels(source) {
    const config = getWikiConfig?.()
    if (!config?.labelsUrl) return

    await ensureWikiLinkLabelsInCache(
      wikiLabelCache,
      config.labelsUrl,
      config.memoId ?? null,
      source,
    )
  }

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
    return collectDocumentSegments().fullSource
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
      normalizeBlockSegmentText(getWysiwygSourceValue(host)),
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
    void renderFromSourceInternal(normalizedSource).finally(() => {
      revealDocumentOffset(normalizedSource, restoreCursor ?? 0)
      finishRenderFromSource(normalizedSource)
    })
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

  function resolveUnitAdocSource(unit, explicitSource) {
    if (typeof explicitSource === 'string') return explicitSource

    const stored = getUnitAdocSource(unit)
    if (stored !== undefined) return stored

    const units = [...editorEl.querySelectorAll(':scope > .wysiwyg-unit')].filter(
      (entry) => !entry.classList.contains('wysiwyg-unit--placeholder'),
    )
    const unitIndex = units.indexOf(unit)
    if (unitIndex >= 0) {
      const sourceSegments = buildSourceSegments(normalizeDocumentSource(history.getCurrent()))
      if (unitIndex < sourceSegments.length) {
        return sourceSegments[unitIndex].text
      }
    }

    const fallback = unitToAsciidoc(unit, getMemoId?.()).trim()
    if (fallback && typeof console !== 'undefined') {
      console.warn(
        '[kbmemo wysiwyg] block source recovered from rendered HTML; AsciiDoc round-trip may be lossy',
      )
    }
    return fallback
  }

  function collectDocumentSegments() {
    /** @type {{ unit: HTMLElement, text: string, from: number, to: number }[]} */
    const segments = []
    let offset = 0

    for (const unit of editorEl.querySelectorAll(':scope > .wysiwyg-unit')) {
      if (unit.classList.contains('wysiwyg-unit--placeholder')) continue

      let text = ''
      if (unit.classList.contains('is-source')) {
        const host = unit.querySelector(':scope > .wysiwyg-source-editor')
        if (host instanceof HTMLElement) {
          text = getWysiwygSourceValue(host)
        }
      } else {
        text = resolveUnitAdocSource(/** @type {HTMLElement} */ (unit))
      }

      if (!text.trim() && !hasUnitAdocSource(unit)) continue

      text = normalizeBlockSegmentText(text)
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
      source: sourceSegment.text,
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

  function insertTextAtSelection(text) {
    const view = getActiveSourceView()
    if (!view) return false

    insertTextIntoEditorView(view, text)
    const host = activeSourceUnit?.querySelector(':scope > .wysiwyg-source-editor')
    if (host instanceof HTMLElement && activeSourceUnit) {
      setUnitAdocSource(activeSourceUnit, getWysiwygSourceValue(host))
      scheduleSync()
    }
    return true
  }

  /**
   * @param {string} adoc
   * @returns {'start' | number | undefined}
   */
  function diagramMacroCaretInSource(adoc) {
    const match = adoc.match(/diagram::([^\[\]]+?)(\[[^\]]*\])?/)
    if (!match || match.index === undefined) return undefined
    return match.index
  }

  editorEl.addEventListener('mousedown', (event) => {
    if (event.button !== 0) return
    if (isRendering || isSwitchingUnit) return
    const target = /** @type {HTMLElement} */ (event.target)
    if (target.closest('.wysiwyg-source-editor')) return
    if (target.closest('.cm-wysiwyg-diagram-actions a')) return

    const unit = target.closest('.wysiwyg-unit')
    if (!unit || !editorEl.contains(unit)) return
    if (unit === activeSourceUnit) return

    const clickedDiagram =
      target.closest('.imageblock object[data]') ||
      target.closest('.memo-diagram-missing') ||
      target.closest('.cm-wysiwyg-diagram')

    event.preventDefault()
    activateSourceUnit(/** @type {HTMLElement} */ (unit), {
      caret: clickedDiagram
        ? diagramMacroCaretInSource(getUnitAdocSource(unit) ?? '') ?? 'start'
        : 'start',
    })
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

  function syncFromDom({ forceNotify = false } = {}) {
    if (isApplyingHistory || isRendering || isActiveUnitComposing()) return
    const next = getDocumentSourceForSync()
    const cursor = getCursorPositionForSync(next)
    const changed = commitHistoryChange(next, cursor)
    if (changed || forceNotify) {
      onSourceChange(next)
    }
  }

  async function renderFromSourceInternal(source) {
    isRendering = true
    activeSourceUnit = null
    wikiLabelCache.clear()
    const memoId = getMemoId?.()
    const normalizedSource = memoId
      ? normalizeMemoImagePathsInSource(source, memoId)
      : source
    editorEl.replaceChildren()

    await ensureDocumentWikiLabels(normalizedSource)

    for (const parsed of parseEditUnitsFromSource(normalizedSource)) {
      const wrapper = document.createElement('div')
      wrapper.className = 'wysiwyg-unit'
      wrapper.contentEditable = 'false'
      setUnitAdocSource(wrapper, parsed.adoc)

      if (!parsed.adoc.trim()) {
        wrapper.classList.add('wysiwyg-unit--placeholder')
        appendEmptyParagraphPreview(wrapper)
      } else {
        renderUnitPreview(wrapper, parsed.adoc)
      }

      editorEl.append(wrapper)
    }

    isRendering = false
    void refreshWikiLabelPreviews(normalizedSource)
  }

  function renderFromSource(source) {
    clearTimeout(syncTimer)
    clearTimeout(splitTimer)
    if (activeSourceUnit) {
      deactivateSourceUnit(activeSourceUnit)
    }
    history.reset(normalizeDocumentSource(source))
    isApplyingHistory = true
    return renderFromSourceInternal(source).finally(() => {
      finishRenderFromSource(source)
    })
  }

  function flush() {
    clearTimeout(syncTimer)
    clearTimeout(splitTimer)
    if (activeSourceUnit) {
      deactivateSourceUnit(activeSourceUnit)
    }
    syncFromDom({ forceNotify: true })
    return getDocumentSourceForSync()
  }

  const SCROLL_INTO_VIEW_PADDING_PX = 24

  function getEditorScrollContainer() {
    const scrollRoot = getScrollRoot()
    if (scrollRoot?.contains(editorEl)) return scrollRoot

    let node = editorEl.parentElement
    while (node) {
      const { overflowY } = getComputedStyle(node)
      if ((overflowY === 'auto' || overflowY === 'scroll') && node.scrollHeight > node.clientHeight + 1) {
        return node
      }
      node = node.parentElement
    }
    return null
  }

  /**
   * @param {Element} container
   * @param {DOMRectReadOnly} rect
   * @param {number} [padding]
   */
  function scrollRectIntoContainer(container, rect, padding = SCROLL_INTO_VIEW_PADDING_PX) {
    const containerRect = container.getBoundingClientRect()
    if (rect.top < containerRect.top + padding) {
      container.scrollTop += rect.top - containerRect.top - padding
    } else if (rect.bottom > containerRect.bottom - padding) {
      container.scrollTop += rect.bottom - containerRect.bottom + padding
    }
  }

  /**
   * @param {HTMLElement} unit
   * @param {HTMLElement | null | undefined} [host]
   */
  function scrollUnitIntoView(unit, host) {
    const container = getEditorScrollContainer()
    if (!container) {
      unit.scrollIntoView({ block: 'nearest', inline: 'nearest' })
      return
    }

    scrollRectIntoContainer(container, unit.getBoundingClientRect())

    if (!(host instanceof HTMLElement)) return

    const view = getWysiwygSourceView(host)
    const cursor = view?.dom.querySelector('.cm-cursor, .cm-dropCursor')
    if (cursor instanceof HTMLElement) {
      scrollRectIntoContainer(container, cursor.getBoundingClientRect())
    }
  }

  /**
   * @param {HTMLElement} unit
   * @param {HTMLElement | null | undefined} [host]
   */
  function scheduleScrollUnitIntoView(unit, host) {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => scrollUnitIntoView(unit, host))
    })
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
        scheduleScrollUnitIntoView(unit, host)
      }
      return
    }

    isSwitchingUnit = true
    if (activeSourceUnit) {
      deactivateSourceUnit(activeSourceUnit)
    }
    removeEmptyRenderedUnits(new Set([unit]))

    unit.classList.remove('wysiwyg-unit--placeholder')

    const initialSource = resolveUnitAdocSource(unit, source)
    setUnitAdocSource(unit, initialSource)
    unit.replaceChildren()
    unit.classList.add('is-source')
    unit.contentEditable = 'false'

    const host = createSourceEditorHost(initialSource, {
      onChange: () => {
        setUnitAdocSource(unit, getWysiwygSourceValue(host))
        scheduleSplitCheck(host)
        scheduleSync()
      },
      onKeyDown: (event, view) => handleSourceKeydown(event, view, activateSourceUnit, getUnitText),
      onPaste: webPasteHandler,
      onContextMenu: (event, view) => {
        void openWysiwygContextMenu(event, () => view)
      },
      onModF: () => openDocumentSearch(),
      onUndo: () => undoDocument(),
      onRedo: () => redoDocument(),
    }, wikiExtensions)
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
    scheduleScrollUnitIntoView(unit, host)
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
    setUnitAdocSource(unit, adoc)

    if (!adoc.trim()) {
      const units = editorEl.querySelectorAll(':scope > .wysiwyg-unit')
      if (units.length <= 1) {
        restoreEmptyParagraphPreview(unit)
        if (activeSourceUnit === unit) {
          activeSourceUnit = null
        }
        return
      }
      removeEmptyUnit(unit)
      return
    }

    renderUnitPreview(unit, adoc)
    void ensureDocumentWikiLabels(adoc).then(() => {
      if (!unit.isConnected || unit.classList.contains('is-source')) return
      renderUnitPreview(unit, adoc)
    })

    unit.classList.remove('is-source')
    unit.contentEditable = 'false'

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
    if (editorEl.querySelectorAll(':scope > .wysiwyg-unit').length === 0) {
      ensureEmptyDocumentEditable()
    }
  }

  /**
   * @param {Set<HTMLElement>} keep
   */
  function removeEmptyRenderedUnits(keep) {
    for (const unit of [...editorEl.querySelectorAll(':scope > .wysiwyg-unit')]) {
      if (keep.has(unit)) continue
      if (unit.classList.contains('is-source')) continue
      if (!unitToAsciidoc(unit, getMemoId?.()).trim()) {
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
    const selectionStart = getWysiwygSourceSelection(host)
    const cursorLine = source.slice(0, selectionStart).split('\n').length - 1

    const tableSplit = getTableParagraphSplit(source, cursorLine)
    if (tableSplit) {
      splitIntoTableAndParagraph(host, source, selectionStart, tableSplit)
      return
    }

    if (!shouldSplitEditUnits(source, cursorLine)) return

    const allUnits = parseEditUnitsFromSource(source)
    const activeIndex = getActiveUnitIndex(allUnits, cursorLine)
    const activeUnit = allUnits[activeIndex]
    let caret = getCaretOffsetInUnit(source, activeUnit, selectionStart)

    let parsedUnits = allUnits.filter((unit) => unit.adoc.trim())
    let filteredActiveIndex = parsedUnits.indexOf(activeUnit)

    if (filteredActiveIndex < 0 && !activeUnit.adoc.trim()) {
      const paragraphAdoc = source
        .split('\n')
        .slice(activeUnit.startLine)
        .join('\n')
        .replace(/^\n+/, '')
      let insertAt = parsedUnits.findIndex((unit) => unit.startLine > activeUnit.startLine)
      if (insertAt < 0) insertAt = parsedUnits.length
      const paragraphUnit = {
        adoc: paragraphAdoc,
        startLine: activeUnit.startLine,
        endLine: activeUnit.endLine,
      }
      parsedUnits = [
        ...parsedUnits.slice(0, insertAt),
        paragraphUnit,
        ...parsedUnits.slice(insertAt),
      ]
      filteredActiveIndex = insertAt
      caret = getCaretInFollowingBlock(source, activeUnit.startLine, selectionStart)
    }

    if (filteredActiveIndex < 0) return

    replaceActiveUnitWithSplit(host, parsedUnits, filteredActiveIndex, caret)
  }

  /**
   * @param {HTMLElement} host
   * @param {string} source
   * @param {number} selectionStart
   * @param {{ tableAdoc: string, paragraphAdoc: string, tableEndLine: number }} tableSplit
   */
  function splitIntoTableAndParagraph(host, source, selectionStart, tableSplit) {
    const { tableAdoc, paragraphAdoc, tableEndLine } = tableSplit
    const caret = getCaretInFollowingBlock(source, tableEndLine + 1, selectionStart)
    replaceActiveUnitWithSplit(
      host,
      [
        { adoc: tableAdoc, startLine: 0, endLine: 0 },
        { adoc: paragraphAdoc, startLine: 0, endLine: 0 },
      ],
      1,
      caret,
    )
  }

  /**
   * @param {HTMLElement} host
   * @param {{ adoc: string }[]} parsedUnits
   * @param {number} activeIndex
   * @param {number} caret
   */
  function replaceActiveUnitWithSplit(host, parsedUnits, activeIndex, caret) {
    isSwitchingUnit = true
    clearTimeout(splitTimer)

    destroyWysiwygSourceEditor(host)

    const currentUnit = /** @type {HTMLElement} */ (activeSourceUnit)
    const newElements = parsedUnits.map((unitData, index) =>
      buildUnitElement(unitData.adoc, index === activeIndex),
    )

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

  splitUnitOnBlankLineFromView = (view) => {
    if (isSwitchingUnit || isRendering) return

    const host = view.dom.closest('.wysiwyg-source-editor')
    if (!(host instanceof HTMLElement) || activeSourceUnit !== host.closest('.wysiwyg-unit')) return

    const source = view.state.doc.toString()
    const head = view.state.selection.main.head
    const lineIndex = source.slice(0, head).split('\n').length - 1
    const line = view.state.doc.lineAt(head)
    if (line.text.trim() !== '') return

    const preserveIndent = isIndentLiteralBlock(source)
    const split = preserveIndent
      ? splitIndentLiteralAtBlankLine(source, lineIndex)
      : splitParagraphAtBlankLine(source, lineIndex)
    const beforeAdoc = preserveIndent ? split.literalAdoc : split.beforeAdoc
    const afterAdoc = split.afterAdoc

    /** @type {{ adoc: string, startLine: number, endLine: number }[]} */
    const parsedUnits = []

    if (beforeAdoc) {
      for (const unit of parseEditUnitsFromSource(beforeAdoc)) {
        parsedUnits.push({ adoc: unit.adoc, startLine: 0, endLine: 0 })
      }
    }

    let activeIndex = 0
    if (afterAdoc.trim()) {
      activeIndex = parsedUnits.length
      for (const unit of parseEditUnitsFromSource(afterAdoc)) {
        parsedUnits.push({ adoc: unit.adoc, startLine: 0, endLine: 0 })
      }
    } else {
      parsedUnits.push({ adoc: '', startLine: 0, endLine: 0 })
      activeIndex = parsedUnits.length - 1
    }

    if (parsedUnits.length === 0) {
      parsedUnits.push({ adoc: '', startLine: 0, endLine: 0 })
      activeIndex = 0
    }

    replaceActiveUnitWithSplit(host, parsedUnits, activeIndex, 0)
  }

  /**
   * @param {string} adoc
   * @param {boolean} asSource
   */
  function buildUnitElement(adoc, asSource) {
    const wrapper = document.createElement('div')
    wrapper.className = 'wysiwyg-unit'
    wrapper.contentEditable = 'false'
    setUnitAdocSource(wrapper, adoc)

    if (asSource) {
      wrapper.classList.add('is-source')
      wrapper.append(
        createSourceEditorHost(adoc, {
          onChange: () => {
            const host = wrapper.querySelector('.wysiwyg-source-editor')
            if (host instanceof HTMLElement) {
              setUnitAdocSource(wrapper, getWysiwygSourceValue(host))
              scheduleSplitCheck(host)
            }
            scheduleSync()
          },
          onKeyDown: (event, view) => handleSourceKeydown(event, view, activateSourceUnit, getUnitText),
          onContextMenu: (event, view) => {
            void openWysiwygContextMenu(event, () => view)
          },
          onModF: () => openDocumentSearch(),
          onUndo: () => undoDocument(),
          onRedo: () => redoDocument(),
        }, wikiExtensions),
      )
      return wrapper
    }

    renderUnitPreview(wrapper, adoc)
    return wrapper
  }

  function getUnitText(unit) {
    if (unit.classList.contains('is-source')) {
      const host = unit.querySelector(':scope > .wysiwyg-source-editor')
      if (host instanceof HTMLElement) {
        return getWysiwygSourceValue(host)
      }
    }
    return resolveUnitAdocSource(/** @type {HTMLElement} */ (unit))
  }

  function wrapUnits(container = editorEl, { skipDeactivate = false } = {}) {
    if (!skipDeactivate && activeSourceUnit) {
      deactivateSourceUnit(activeSourceUnit)
    }
    flattenAndWrapUnits(container)
  }

  function isEmptyDocumentSource(source) {
    return !normalizeDocumentSource(source).trim()
  }

  /**
   * @param {HTMLElement} wrapper
   */
  function appendEmptyParagraphPreview(wrapper) {
    const empty = document.createElement('div')
    empty.className = 'paragraph wysiwyg-empty-paragraph'
    empty.innerHTML = '<p><br class="wysiwyg-empty-paragraph-marker" aria-hidden="true" /></p>'
    wrapper.append(empty)
  }

  /**
   * @param {HTMLElement} unit
   */
  function restoreEmptyParagraphPreview(unit) {
    const host = unit.querySelector(':scope > .wysiwyg-source-editor')
    if (host instanceof HTMLElement) {
      destroyWysiwygSourceEditor(host)
    }
    unit.classList.remove('is-source')
    unit.classList.add('wysiwyg-unit--placeholder')
    unit.contentEditable = 'false'
    unit.replaceChildren()
    appendEmptyParagraphPreview(unit)
    setUnitAdocSource(unit, '')
  }

  function ensureEmptyDocumentEditable() {
    if (isRendering || isSwitchingUnit) return

    let unit = editorEl.querySelector(':scope > .wysiwyg-unit')
    if (!unit) {
      unit = document.createElement('div')
      unit.className = 'wysiwyg-unit wysiwyg-unit--placeholder'
      unit.contentEditable = 'false'
      setUnitAdocSource(unit, '')
      appendEmptyParagraphPreview(unit)
      editorEl.append(unit)
    }

    if (!unit.classList.contains('is-source')) {
      activateSourceUnit(/** @type {HTMLElement} */ (unit), { caret: 'start' })
    }
  }

  function finishRenderFromSource(source) {
    isApplyingHistory = false
    if (isEmptyDocumentSource(source)) {
      ensureEmptyDocumentEditable()
    }
  }

  return {
    renderFromSource,
    flush,
    getDocumentSource,
    wrapUnits,
    getActiveSourceView,
    ensureSourceEditable,
    insertTextAtSelection,
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
function createSourceEditorHost(source, { onChange, onKeyDown, onPaste, onContextMenu, onModF, onUndo, onRedo }, extensions) {
  return createWysiwygSourceEditor(source, {
    extensions,
    onChange: () => onChange(),
    onKeyDown,
    onPaste,
    onContextMenu,
    onModF,
    onUndo,
    onRedo,
  })
}

/**
 * @param {HTMLElement} unit
 */
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
 * @param {(unit: HTMLElement) => string} getUnitText
 */
function handleSourceKeydown(event, view, activateSourceUnit, getUnitText) {
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
    const step = event.key === 'ArrowUp' ? -1 : 1
    let nextIndex = index + step

    while (nextIndex >= 0 && nextIndex < units.length) {
      const nextUnit = units[nextIndex]
      if (nextUnit instanceof HTMLElement && getUnitText(nextUnit).trim()) {
        event.preventDefault()
        activateSourceUnit(nextUnit, { caret: event.key === 'ArrowUp' ? 'end' : 'start' })
        return true
      }
      nextIndex += step
    }

    return false
  }

  if (event.key !== 'Tab') return false

  event.preventDefault()
  const spaces = '  '
  view.dispatch(view.state.replaceSelection(spaces))
  return true
}
