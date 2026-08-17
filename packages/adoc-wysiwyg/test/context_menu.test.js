// @vitest-environment happy-dom

import { beforeEach, describe, expect, it, vi } from 'vitest'
import { EditorState } from '@codemirror/state'
import { EditorView } from '@codemirror/view'

beforeEach(() => {
  document.body.replaceChildren()
  vi.resetModules()
})

describe('editor context menu', () => {
  it('shows search, clipboard, and extra items', async () => {
    const { openEditorContextMenu } = await import('../editorContextMenu.js')
    const { view } = createView('hello world')
    const extraAction = vi.fn()

    await openEditorContextMenu(contextMenuEvent(), {
      getView: () => view,
      getExtraItems: () => [{ label: 'コミット', action: extraAction }],
    })

    const labels = menuLabels()
    expect(labels).toContain('検索・置換…')
    expect(labels).toContain('切り取り')
    expect(labels).toContain('コピー')
    expect(labels).toContain('貼り付け')
    expect(labels).toContain('コミット')
    expect(document.querySelectorAll('.editor-context-menu-separator').length).toBeGreaterThan(0)

    const extraButton = [...document.querySelectorAll('.editor-context-menu-item')].find(
      (button) => button.querySelector('.editor-context-menu-label')?.textContent === 'コミット',
    )
    extraButton?.dispatchEvent(new MouseEvent('click', { bubbles: true }))
    expect(extraAction).toHaveBeenCalledOnce()

    view.destroy()
  })

  it('re-appends the menu after it is detached from the document', async () => {
    const { openEditorContextMenu } = await import('../editorContextMenu.js')
    const { view } = createView('hello')

    await openEditorContextMenu(contextMenuEvent(), { getView: () => view })
    const first = document.querySelector('.editor-context-menu')
    expect(first).toBeInstanceOf(HTMLElement)
    expect(first?.hidden).toBe(false)

    first?.remove()
    expect(document.querySelector('.editor-context-menu')).toBeNull()

    await openEditorContextMenu(contextMenuEvent(), { getView: () => view })
    const second = document.querySelector('.editor-context-menu')
    expect(second).toBeInstanceOf(HTMLElement)
    expect(second).not.toBe(first)
    expect(second?.isConnected).toBe(true)
    expect(second?.hidden).toBe(false)

    view.destroy()
  })

  it('does not add extra items or a trailing separator when getExtraItems is empty', async () => {
    const { openEditorContextMenu } = await import('../editorContextMenu.js')
    const { view } = createView('hello')

    await openEditorContextMenu(contextMenuEvent(), {
      getView: () => view,
      getExtraItems: () => [],
    })

    expect(menuLabels()).not.toContain('コミット')
    const separators = document.querySelectorAll('.editor-context-menu-separator')
    const items = document.querySelectorAll('.editor-context-menu-item, .editor-context-menu-separator')
    expect(items[items.length - 1]).not.toBe(separators[separators.length - 1])

    view.destroy()
  })

  it('stops opening from a container after the disposer runs', async () => {
    const { initEditorContextMenus } = await import('../editorContextMenu.js')
    const { view } = createView('hello')
    const container = document.createElement('div')
    document.body.append(container)

    const dispose = initEditorContextMenus({
      live: {
        container,
        getView: () => view,
      },
    })

    container.dispatchEvent(contextMenuEvent())
    await Promise.resolve()
    const menu = document.querySelector('.editor-context-menu')
    expect(menu?.hidden).toBe(false)

    menu.hidden = true
    dispose()
    container.dispatchEvent(contextMenuEvent())
    await Promise.resolve()
    expect(document.querySelector('.editor-context-menu')?.hidden).toBe(true)

    view.destroy()
  })
})

function createView(doc) {
  const host = document.createElement('div')
  document.body.append(host)
  const view = new EditorView({
    state: EditorState.create({ doc }),
    parent: host,
  })
  return { view, host }
}

function contextMenuEvent() {
  return new MouseEvent('contextmenu', {
    bubbles: true,
    cancelable: true,
    clientX: 24,
    clientY: 32,
  })
}

function menuLabels() {
  return [...document.querySelectorAll('.editor-context-menu-label')].map((el) => el.textContent)
}
