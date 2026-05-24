import { webHtmlToAsciidoc } from '@kbmemo/adoc-codemirror'
import { appendWebPasteAttribution } from './webPasteAttribution.js'
import { extractWebPasteMetadata } from './webPasteMetadata.js'
import { promptWebPasteSource } from './webPasteDialog.js'

/**
 * @typedef {{ url?: string, title?: string }} WebPasteMetadata
 */

/**
 * @param {DataTransfer | null | undefined} clipboardData
 */
export function hasWebHtmlPaste(clipboardData) {
  if (!clipboardData?.types?.includes('text/html')) return false
  const html = clipboardData.getData('text/html') ?? ''
  return html.trim().length > 0
}

/**
 * Read clipboard contents synchronously during a paste event.
 *
 * @param {DataTransfer} clipboardData
 * @returns {{ html: string, plain: string, metadata: WebPasteMetadata, adoc: string }}
 */
export function captureWebPasteFromClipboard(clipboardData) {
  const html = clipboardData.getData('text/html') ?? ''
  const plain = clipboardData.getData('text/plain') ?? ''
  const metadata = extractWebPasteMetadata(clipboardData, html)
  const adoc = webHtmlToAsciidoc(html)

  return { html, plain, metadata, adoc }
}

/**
 * @param {{ html: string, plain: string, metadata: WebPasteMetadata, adoc?: string }} captured
 * @returns {Promise<{ text: string } | { fallbackPlain: string } | null>}
 */
export async function resolveWebPasteContent(captured) {
  const adoc = captured.adoc ?? webHtmlToAsciidoc(captured.html)
  if (!adoc.trim()) {
    return captured.plain.trim() ? { fallbackPlain: captured.plain } : null
  }

  let metadata = captured.metadata
  if (!metadata.url) {
    const dialog = await promptWebPasteSource({
      title: metadata.title,
      url: metadata.url,
    })

    if (dialog.action === 'cancel') {
      return captured.plain.trim() ? { fallbackPlain: captured.plain } : null
    }
    if (dialog.action === 'skip') {
      return { text: adoc }
    }
    metadata = {
      url: dialog.metadata?.url,
      title: dialog.metadata?.title || metadata.title,
    }
  }

  if (metadata.url) {
    return { text: appendWebPasteAttribution(adoc, metadata) }
  }

  return { text: adoc }
}

/**
 * @param {{ text: string } | { fallbackPlain: string } | null} result
 */
export function textFromWebPasteResult(result) {
  if (!result) return null
  if ('text' in result) return result.text
  if ('fallbackPlain' in result) return result.fallbackPlain
  return null
}

/**
 * @param {import('@codemirror/view').EditorView} view
 * @param {string} text
 */
export function insertTextIntoEditorView(view, text) {
  const { from, to } = view.state.selection.main
  view.dispatch({
    changes: { from, to, insert: text },
    selection: { anchor: from + text.length, head: from + text.length },
    scrollIntoView: true,
  })
  view.focus()
}

/**
 * @param {{ insertText: (text: string, view?: import('@codemirror/view').EditorView | null) => void }} handlers
 */
export function createWebPasteHandler({ insertText }) {
  return (event, view) => {
    const clipboard = event.clipboardData
    if (!clipboard || !hasWebHtmlPaste(clipboard)) return false

    const captured = captureWebPasteFromClipboard(clipboard)
    if (!captured.adoc.trim()) return false

    event.preventDefault()

    void (async () => {
      const result = await resolveWebPasteContent(captured)
      const text = textFromWebPasteResult(result)
      if (text) insertText(text, view ?? null)
    })()

    return true
  }
}

/**
 * @param {DataTransfer | null | undefined} clipboardData
 */
export function fallbackPlainTextFromClipboard(clipboardData) {
  return clipboardData?.getData('text/plain') ?? ''
}
