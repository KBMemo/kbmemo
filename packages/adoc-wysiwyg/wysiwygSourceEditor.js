import { EditorState } from '@codemirror/state'
import { EditorView, ViewPlugin } from '@codemirror/view'
import { search } from '@codemirror/search'
import { asciidocHighlight } from '@kbmemo/adoc-codemirror'
import { createModFKeymap } from './searchKeybindings.js'
import { isModRedo, isModZ } from './wysiwygHistory.js'

/** @type {WeakMap<HTMLElement, EditorView>} */
const viewByHost = new WeakMap()

/** @type {WeakMap<EditorView, number>} */
const resizeFrameByView = new WeakMap()

/** @type {WeakMap<HTMLElement, () => void>} */
const historyKeyCleanupByHost = new WeakMap()

/** @type {WeakMap<HTMLElement, boolean>} */
const composingByHost = new WeakMap()

/**
 * @param {HTMLElement} host
 */
export function isWysiwygSourceComposing(host) {
  return composingByHost.get(host) ?? false
}

/**
 * @param {string} source
 * @param {{ extensions?: import('@codemirror/state').Extension[], onChange?: (view: EditorView) => void, onKeyDown?: (event: KeyboardEvent, view: EditorView) => boolean | void, onPaste?: (event: ClipboardEvent, view: EditorView) => boolean | void, onContextMenu?: (event: MouseEvent, view: EditorView) => void, onModF?: (view: EditorView) => void, onUndo?: () => boolean, onRedo?: () => boolean }} [handlers]
 */
export function createWysiwygSourceEditor(source, { extensions = [], onChange, onKeyDown, onPaste, onContextMenu, onModF, onUndo, onRedo } = {}) {
  const host = document.createElement('div')
  host.className = 'wysiwyg-source-editor'

  const view = new EditorView({
    state: EditorState.create({
      doc: source,
      extensions: [
        onModF ? createModFKeymap(onModF) : [],
        search(),
        asciidocHighlight,
        EditorView.lineWrapping,
        wysiwygAutoHeightExtension(),
        ...extensions,
        EditorView.updateListener.of((update) => {
          if (update.docChanged && !composingByHost.get(host)) {
            onChange?.(view)
          }
        }),
        EditorView.domEventHandlers({
          compositionstart() {
            composingByHost.set(host, true)
            return false
          },
          compositionend(event, view) {
            composingByHost.set(host, false)
            onChange?.(view)
            return false
          },
          compositioncancel() {
            composingByHost.set(host, false)
            return false
          },
          keydown(event, view) {
            return onKeyDown?.(event, view) === true
          },
          paste(event, view) {
            return onPaste?.(event, view) === true
          },
          contextmenu(event, view) {
            onContextMenu?.(event, view)
            return true
          },
        }),
        wysiwygSourceTheme,
      ],
    }),
    parent: host,
  })

  if (onUndo || onRedo) {
    installDocumentHistoryKeyHandlers(host, view.dom, onUndo, onRedo)
  }

  viewByHost.set(host, view)
  scheduleWysiwygSourceEditorResize(view)
  return host
}

function wysiwygAutoHeightExtension() {
  return ViewPlugin.fromClass(
    class {
      /** @param {EditorView} view */
      constructor(view) {
        this.view = view
        scheduleWysiwygSourceEditorResize(view)
      }

      update(update) {
        scheduleWysiwygSourceEditorResize(update.view)
      }

      destroy() {
        cancelWysiwygSourceEditorResize(this.view)
      }
    },
  )
}

/**
 * @param {EditorView} view
 */
export function scheduleWysiwygSourceEditorResize(view) {
  const existing = resizeFrameByView.get(view)
  if (existing != null) cancelAnimationFrame(existing)

  const frame = requestAnimationFrame(() => {
    resizeFrameByView.delete(view)
    if (!view.dom.isConnected) return
    view.requestMeasure()
    resizeWysiwygSourceEditor(view)
  })
  resizeFrameByView.set(view, frame)
}

/**
 * @param {EditorView | undefined} view
 */
function cancelWysiwygSourceEditorResize(view) {
  if (!view) return
  const existing = resizeFrameByView.get(view)
  if (existing != null) cancelAnimationFrame(existing)
  resizeFrameByView.delete(view)
}

const wysiwygSourceTheme = EditorView.theme({
  '&': {
    fontSize: '0.875rem',
  },
  '&.cm-focused': {
    outline: 'none',
  },
  '.cm-scroller': {
    fontFamily: "ui-monospace, 'Cascadia Code', 'Source Code Pro', Menlo, monospace",
    lineHeight: '1.6',
    overflow: 'visible',
  },
  '.cm-content': {
    padding: '0.75rem 1rem',
    minHeight: '2.5rem',
  },
  '.cm-gutters': {
    display: 'none',
  },
})

/**
 * @param {EditorView} view
 */
export function resizeWysiwygSourceEditor(view) {
  const editorEl = view.dom
  const host = editorEl.closest('.wysiwyg-source-editor')
  const contentHeight = Math.ceil(view.contentHeight)
  const height = `${contentHeight}px`

  editorEl.style.height = 'auto'
  editorEl.style.height = height

  if (host instanceof HTMLElement) {
    host.style.height = 'auto'
    host.style.height = height
  }
}

/**
 * @param {HTMLElement} host
 * @returns {EditorView | null}
 */
export function getWysiwygSourceView(host) {
  return viewByHost.get(host) ?? null
}

/**
 * @param {HTMLElement} host
 */
export function destroyWysiwygSourceEditor(host) {
  historyKeyCleanupByHost.get(host)?.()
  historyKeyCleanupByHost.delete(host)
  composingByHost.delete(host)

  const view = viewByHost.get(host)
  if (view) {
    cancelWysiwygSourceEditorResize(view)
    view.destroy()
    viewByHost.delete(host)
  }
}

/**
 * @param {HTMLElement} host
 */
export function getWysiwygSourceValue(host) {
  return getWysiwygSourceView(host)?.state.doc.toString() ?? ''
}

/**
 * @param {HTMLElement} host
 */
export function getWysiwygSourceSelection(host) {
  return getWysiwygSourceView(host)?.state.selection.main.head ?? 0
}

/**
 * @param {HTMLElement} host
 * @param {number} position
 */
export function setWysiwygSourceSelection(host, position) {
  const view = getWysiwygSourceView(host)
  if (!view) return
  const pos = Math.max(0, Math.min(position, view.state.doc.length))
  view.dispatch({ selection: { anchor: pos, head: pos } })
  scheduleWysiwygSourceEditorResize(view)
}

/**
 * @param {HTMLElement} host
 * @param {number} from
 * @param {number} to
 */
export function setWysiwygSourceRange(host, from, to) {
  const view = getWysiwygSourceView(host)
  if (!view) return
  const length = view.state.doc.length
  const anchor = Math.max(0, Math.min(from, length))
  const head = Math.max(0, Math.min(to, length))
  view.dispatch({ selection: { anchor, head } })
  scheduleWysiwygSourceEditorResize(view)
}

/**
 * @param {HTMLElement} host
 */
export function focusWysiwygSourceEditor(host) {
  getWysiwygSourceView(host)?.focus()
}

/**
 * @param {HTMLElement} host
 * @param {string} source
 */
export function replaceWysiwygSourceDocument(host, source) {
  const view = getWysiwygSourceView(host)
  if (!view) return
  view.dispatch({
    changes: { from: 0, to: view.state.doc.length, insert: source },
  })
  scheduleWysiwygSourceEditorResize(view)
}

/**
 * @param {HTMLElement} host
 * @param {HTMLElement} dom
 * @param {(() => boolean) | undefined} onUndo
 * @param {(() => boolean) | undefined} onRedo
 */
function installDocumentHistoryKeyHandlers(host, dom, onUndo, onRedo) {
  /** @param {KeyboardEvent} event */
  const handler = (event) => {
    if (onUndo && isModZ(event)) {
      event.preventDefault()
      event.stopPropagation()
      onUndo()
      return
    }
    if (onRedo && isModRedo(event)) {
      event.preventDefault()
      event.stopPropagation()
      onRedo()
    }
  }

  dom.addEventListener('keydown', handler, { capture: true })
  historyKeyCleanupByHost.set(host, () => {
    dom.removeEventListener('keydown', handler, { capture: true })
  })
}
