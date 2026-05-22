/**
 * @param {string} adoc
 * @param {{ url?: string, title?: string }} metadata
 * @returns {string}
 */
export function appendWebPasteAttribution(adoc, { url, title }) {
  const trimmedUrl = url?.trim()
  if (!trimmedUrl) return adoc

  const label = buildAttributionLabel(title, trimmedUrl)
  const footer = `link:${trimmedUrl}[${escapeLinkLabel(label)}]`
  const body = adoc.trimEnd()
  return body ? `${body}\n\n${footer}` : footer
}

/**
 * @param {string | undefined} title
 * @param {string} url
 */
function buildAttributionLabel(title, url) {
  const trimmedTitle = title?.trim()
  if (trimmedTitle) return `出典: ${trimmedTitle}`
  return '出典'
}

/**
 * @param {string} text
 */
function escapeLinkLabel(text) {
  return text.replace(/\\/g, '\\\\').replace(/\[/g, '\\[').replace(/\]/g, '\\]')
}
