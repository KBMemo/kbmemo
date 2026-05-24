const isMac =
  typeof navigator !== 'undefined' &&
  /Mac|iPod|iPhone|iPad/.test(navigator.platform)

const isLinux =
  typeof navigator !== 'undefined' &&
  !isMac &&
  /Linux/.test(navigator.userAgent)

/**
 * @param {string} key
 * @param {{ shift?: boolean }} [options]
 */
export function formatModShortcut(key, { shift = false } = {}) {
  if (isMac) {
    return `${shift ? '⌘⇧' : '⌘'}${key.toUpperCase()}`
  }

  const parts = ['Ctrl']
  if (shift) parts.push('Shift')
  parts.push(key.toUpperCase())
  return parts.join('+')
}

export function formatRedoShortcut() {
  if (isMac) return formatModShortcut('z', { shift: true })
  if (isLinux) return 'Ctrl+Shift+Z'
  return 'Ctrl+Y'
}

export const MENU_SHORTCUTS = {
  search: formatModShortcut('f'),
  undo: formatModShortcut('z'),
  redo: formatRedoShortcut(),
  cut: formatModShortcut('x'),
  copy: formatModShortcut('c'),
  paste: formatModShortcut('v'),
  selectAll: formatModShortcut('a'),
}
