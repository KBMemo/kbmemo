import { redo, redoDepth, undo, undoDepth } from '@codemirror/commands'
import { KBMEMO_CLIP_MIME, parseKbmemoClipJson } from './webPasteMetadata.js'
import {
  insertTextIntoEditorView,
  resolveWebPasteContent,
  textFromWebPasteResult,
} from './webPaste.js'
import { webHtmlToAsciidoc } from '@kbmemo/adoc-codemirror'
import { extractWebPasteMetadataFromHtml } from './webPasteHtmlMetadata.js'

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export function canUndoInView(view) {
  return undoDepth(view.state) > 0
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export function canRedoInView(view) {
  return redoDepth(view.state) > 0
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export function undoInView(view) {
  if (!undo(view)) return
  view.focus()
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export function redoInView(view) {
  if (!redo(view)) return
  view.focus()
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export async function copyFromView(view) {
  const { from, to } = view.state.selection.main
  if (from === to) return

  const text = view.state.sliceDoc(from, to)
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    copyWithExecCommand(text)
  }
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export async function cutFromView(view) {
  const { from, to } = view.state.selection.main
  if (from === to) return

  const text = view.state.sliceDoc(from, to)
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    copyWithExecCommand(text)
  }

  view.dispatch({
    changes: { from, to, insert: '' },
    selection: { anchor: from },
  })
  view.focus()
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export async function pasteToView(view) {
  const captured = await readClipboardForWebPaste()
  if (captured?.adoc.trim()) {
    const result = await resolveWebPasteContent(captured)
    const text = textFromWebPasteResult(result)
    if (text) {
      insertTextIntoEditorView(view, text)
      return
    }
  }

  const plain = captured?.plain ?? await readPlainTextFromClipboard()
  if (!plain) {
    view.focus()
    return
  }

  insertTextIntoEditorView(view, plain)
}

/**
 * @returns {Promise<{ html: string, plain: string, metadata: { url?: string, title?: string }, adoc: string } | null>}
 */
async function readClipboardForWebPaste() {
  if (!navigator.clipboard.read) return null

  try {
    const items = await navigator.clipboard.read()
    let html = ''
    let plain = ''
    /** @type {{ url?: string, title?: string }} */
    let metadata = {}

    for (const item of items) {
      if (!html && item.types.includes('text/html')) {
        html = await (await item.getType('text/html')).text()
      }
      if (!plain && item.types.includes('text/plain')) {
        plain = await (await item.getType('text/plain')).text()
      }
      if (!metadata.url && item.types.includes(KBMEMO_CLIP_MIME)) {
        const clip = parseKbmemoClipJson(await (await item.getType(KBMEMO_CLIP_MIME)).text())
        if (clip) {
          metadata = {
            url: metadata.url || clip.url,
            title: metadata.title || clip.title,
          }
        }
      }
      if (!metadata.url && item.types.includes('text/uri-list')) {
        const uri = await (await item.getType('text/uri-list')).text()
        const url = firstUriFromList(uri)
        if (url) metadata = { ...metadata, url }
      }
    }

    if (html.trim()) {
      const fromHtml = extractWebPasteMetadataFromHtml(html)
      metadata = {
        url: metadata.url || fromHtml.url,
        title: metadata.title || fromHtml.title,
      }
    }

    if (!html.trim()) return plain || metadata.url ? { html, plain, metadata, adoc: '' } : null

    return {
      html,
      plain,
      metadata,
      adoc: webHtmlToAsciidoc(html),
    }
  } catch {
    return null
  }
}

/**
 * @returns {Promise<string>}
 */
async function readPlainTextFromClipboard() {
  try {
    return await navigator.clipboard.readText()
  } catch {
    return ''
  }
}

/**
 * @param {string} raw
 */
function firstUriFromList(raw) {
  return raw
    .split('\n')
    .map((line) => line.trim())
    .find((line) => line && !line.startsWith('#'))
}

/**
 * @param {import('@codemirror/view').EditorView} view
 */
export function selectAllInView(view) {
  view.dispatch({
    selection: { anchor: 0, head: view.state.doc.length },
  })
  view.focus()
}

/**
 * @param {string} text
 */
function copyWithExecCommand(text) {
  const textarea = document.createElement('textarea')
  textarea.value = text
  textarea.setAttribute('readonly', '')
  textarea.style.position = 'fixed'
  textarea.style.left = '-9999px'
  document.body.append(textarea)
  textarea.select()
  document.execCommand('copy')
  textarea.remove()
}

/**
 * @param {string} [text]
 */
export async function copyPlainText(text) {
  const value = text ?? window.getSelection()?.toString() ?? ''
  if (!value) return
  try {
    await navigator.clipboard.writeText(value)
  } catch {
    copyWithExecCommand(value)
  }
}
