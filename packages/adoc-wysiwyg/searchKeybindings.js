import { Prec } from '@codemirror/state'
import { keymap } from '@codemirror/view'

/**
 * @param {KeyboardEvent} event
 */
export function isModF(event) {
  return (
    (event.ctrlKey || event.metaKey) &&
    !event.shiftKey &&
    !event.altKey &&
    event.key.toLowerCase() === 'f'
  )
}

/**
 * @param {(view: import('@codemirror/view').EditorView) => void} onSearch
 */
export function createModFKeymap(onSearch) {
  return Prec.high(
    keymap.of([
      {
        key: 'Mod-f',
        preventDefault: true,
        run(view) {
          onSearch(view)
          return true
        },
      },
    ]),
  )
}
