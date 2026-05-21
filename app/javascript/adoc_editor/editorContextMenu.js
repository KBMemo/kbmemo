import {
  canRedoInView,
  canUndoInView,
  copyFromView,
  copyPlainText,
  cutFromView,
  pasteToView,
  redoInView,
  selectAllInView,
  undoInView,
} from './editorClipboard.js'
import { openSearchReplaceDialog, openDocumentSearchReplaceDialog, closeSearchReplaceDialog } from './searchReplaceDialog.js'
import { MENU_SHORTCUTS } from './contextMenuShortcut.js'

/** @typedef {{
 *   label: string
 *   action: () => void | Promise<void>
 *   disabled?: boolean
 *   shortcut?: string
 * }} ContextMenuItem */

/** @type {HTMLElement | null} */
let menuEl = null

/**
 * @param {{
 *   live: { container: HTMLElement, getView: () => import('@codemirror/view').EditorView | null | undefined }
 *   preview: { container: HTMLElement, getView: () => import('@codemirror/view').EditorView | null | undefined }
 * }} targets
 */
export function initEditorContextMenus(targets) {
  createContextMenuElement()

  for (const [scope, config] of Object.entries(targets)) {
    config.container.addEventListener('contextmenu', (event) => {
      void openEditorContextMenu(event, { scope, ...config })
    })
  }

  document.addEventListener('click', hideContextMenu)
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      hideContextMenu()
      closeSearchReplaceDialog()
    }
  })
  window.addEventListener('scroll', hideContextMenu, true)
  window.addEventListener('resize', hideContextMenu)
}

/**
 * @param {MouseEvent} event
 * @param {{
 *   scope?: string
 *   getView: () => import('@codemirror/view').EditorView | null | undefined
 *   getDocumentSearchController?: () => import('./searchReplaceDialog.js').DocumentSearchController
 *   getDocumentHistoryController?: () => import('./wysiwygHistory.js').DocumentHistoryController
 *   onBeforeEdit?: (event: MouseEvent) => void | Promise<void>
 * }} config
 */
export async function openEditorContextMenu(event, { scope = 'editor', getView, getDocumentSearchController, getDocumentHistoryController, onBeforeEdit }) {
  if (event.target instanceof HTMLElement && event.target.closest('.editor-context-menu, .search-replace-dialog')) {
    return
  }

  createContextMenuElement()

  event.preventDefault()
  event.stopPropagation()
  hideContextMenu()

  if (onBeforeEdit) {
    await onBeforeEdit(event)
  }

  const view = getView()
  const items =
    scope === 'preview'
      ? buildPreviewMenuItems(view, event)
      : buildEditorMenuItems(view, event, scope, getDocumentSearchController, getDocumentHistoryController)

  showContextMenu(event.clientX, event.clientY, items)
}

function createContextMenuElement() {
  if (menuEl) return
  menuEl = document.createElement('div')
  menuEl.className = 'editor-context-menu'
  menuEl.hidden = true
  menuEl.setAttribute('role', 'menu')
  document.body.append(menuEl)
}

/**
 * @param {import('@codemirror/view').EditorView | null | undefined} view
 * @param {MouseEvent} event
 * @param {string} scope
 * @param {(() => import('./searchReplaceDialog.js').DocumentSearchController) | undefined} getDocumentSearchController
 * @param {(() => import('./wysiwygHistory.js').DocumentHistoryController) | undefined} getDocumentHistoryController
 * @returns {ContextMenuItem[]}
 */
function buildEditorMenuItems(view, event, scope, getDocumentSearchController, getDocumentHistoryController) {
  const hasView = Boolean(view)
  const hasSelection = hasView && view.state.selection.main.from !== view.state.selection.main.to
  const renderedSelection = window.getSelection()?.toString() ?? ''
  const useDocumentSearch = scope === 'wysiwyg' && Boolean(getDocumentSearchController)
  const useDocumentHistory = scope === 'wysiwyg' && Boolean(getDocumentHistoryController)
  const historyController = useDocumentHistory ? getDocumentHistoryController() : null

  if (!hasView && scope === 'wysiwyg') {
    return [
      {
        label: '検索・置換…',
        disabled: !useDocumentSearch,
        shortcut: MENU_SHORTCUTS.search,
        action: () => {
          if (getDocumentSearchController) {
            openDocumentSearchReplaceDialog(getDocumentSearchController(), {
              x: event.clientX,
              y: event.clientY,
              initialSearch: renderedSelection,
            })
          }
        },
      },
      { label: '---' },
      {
        label: '元に戻す',
        disabled: !historyController?.canUndo(),
        shortcut: MENU_SHORTCUTS.undo,
        action: () => historyController?.undo(),
      },
      {
        label: 'やり直し',
        disabled: !historyController?.canRedo(),
        shortcut: MENU_SHORTCUTS.redo,
        action: () => historyController?.redo(),
      },
      { label: '---' },
      {
        label: 'コピー',
        disabled: !renderedSelection,
        shortcut: MENU_SHORTCUTS.copy,
        action: () => copyPlainText(renderedSelection),
      },
    ]
  }

  return [
    {
      label: '検索・置換…',
      disabled: useDocumentSearch ? false : !hasView,
      shortcut: MENU_SHORTCUTS.search,
      action: () => {
        if (useDocumentSearch && getDocumentSearchController) {
          openDocumentSearchReplaceDialog(getDocumentSearchController(), {
            x: event.clientX,
            y: event.clientY,
            initialSearch: hasView
              ? view.state.sliceDoc(view.state.selection.main.from, view.state.selection.main.to)
              : renderedSelection,
          })
          return
        }
        if (!view) return
        openSearchReplaceDialog(view, { x: event.clientX, y: event.clientY })
      },
    },
    { label: '---' },
    {
      label: '元に戻す',
      disabled: useDocumentHistory ? !historyController?.canUndo() : !hasView || !canUndoInView(view),
      shortcut: MENU_SHORTCUTS.undo,
      action: () => {
        if (useDocumentHistory && historyController) {
          historyController.undo()
          return
        }
        if (view) undoInView(view)
      },
    },
    {
      label: 'やり直し',
      disabled: useDocumentHistory ? !historyController?.canRedo() : !hasView || !canRedoInView(view),
      shortcut: MENU_SHORTCUTS.redo,
      action: () => {
        if (useDocumentHistory && historyController) {
          historyController.redo()
          return
        }
        if (view) redoInView(view)
      },
    },
    { label: '---' },
    {
      label: '切り取り',
      disabled: !hasView || !hasSelection,
      shortcut: MENU_SHORTCUTS.cut,
      action: () => view && cutFromView(view),
    },
    {
      label: 'コピー',
      disabled: !hasView || !hasSelection,
      shortcut: MENU_SHORTCUTS.copy,
      action: () => view && copyFromView(view),
    },
    {
      label: '貼り付け',
      disabled: !hasView,
      shortcut: MENU_SHORTCUTS.paste,
      action: () => view && pasteToView(view),
    },
    {
      label: 'すべて選択',
      disabled: !hasView,
      shortcut: MENU_SHORTCUTS.selectAll,
      action: () => view && selectAllInView(view),
    },
  ]
}

/**
 * @param {import('@codemirror/view').EditorView | null | undefined} view
 * @param {MouseEvent} event
 * @returns {ContextMenuItem[]}
 */
function buildPreviewMenuItems(view, event) {
  const selected = window.getSelection()?.toString() ?? ''

  return [
    {
      label: '検索・置換…',
      disabled: !view,
      action: () => {
        if (!view) return
        openSearchReplaceDialog(view, {
          x: event.clientX,
          y: event.clientY,
          initialSearch: selected,
        })
      },
    },
    { label: '---' },
    {
      label: 'コピー',
      disabled: !selected,
      shortcut: MENU_SHORTCUTS.copy,
      action: () => copyPlainText(selected),
    },
  ]
}

/**
 * @param {number} x
 * @param {number} y
 * @param {ContextMenuItem[]} items
 */
function showContextMenu(x, y, items) {
  if (!menuEl) return

  menuEl.replaceChildren()
  for (const item of items) {
    if (item.label === '---') {
      const separator = document.createElement('div')
      separator.className = 'editor-context-menu-separator'
      separator.setAttribute('role', 'separator')
      menuEl.append(separator)
      continue
    }

    const button = document.createElement('button')
    button.type = 'button'
    button.className = 'editor-context-menu-item'
    button.disabled = Boolean(item.disabled)
    button.setAttribute('role', 'menuitem')

    const label = document.createElement('span')
    label.className = 'editor-context-menu-label'
    label.textContent = item.label
    button.append(label)

    if (item.shortcut) {
      const shortcut = document.createElement('span')
      shortcut.className = 'editor-context-menu-shortcut'
      shortcut.textContent = item.shortcut
      button.append(shortcut)
    }

    button.addEventListener('click', () => {
      hideContextMenu()
      void item.action()
    })
    menuEl.append(button)
  }

  menuEl.hidden = false
  menuEl.style.left = '0px'
  menuEl.style.top = '0px'

  const margin = 8
  const rect = menuEl.getBoundingClientRect()
  let left = x
  let top = y

  if (left + rect.width > window.innerWidth - margin) {
    left = window.innerWidth - rect.width - margin
  }
  if (top + rect.height > window.innerHeight - margin) {
    top = window.innerHeight - rect.height - margin
  }

  menuEl.style.left = `${Math.max(margin, left)}px`
  menuEl.style.top = `${Math.max(margin, top)}px`
}

function hideContextMenu() {
  if (menuEl) {
    menuEl.hidden = true
  }
}
