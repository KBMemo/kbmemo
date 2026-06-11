// @vitest-environment happy-dom

import { beforeEach, describe, expect, it, vi } from 'vitest'

beforeEach(() => {
  document.body.replaceChildren()
  vi.resetModules()
  installDialogPolyfill()
})

describe('paste dialogs', () => {
  it('opens the web paste prompt as a named native dialog', async () => {
    const { promptWebPasteSource } = await import('../webPasteDialog.js')

    const resultPromise = promptWebPasteSource({
      url: 'https://example.com/source',
      title: 'Example source',
    })

    const dialog = /** @type {HTMLDialogElement} */ (document.querySelector('.web-paste-dialog'))
    expect(dialog?.tagName).toBe('DIALOG')
    expect(dialog.open).toBe(true)
    expect(dialog.getAttribute('closedby')).toBe('any')
    expect(dialog.getAttribute('aria-labelledby')).toBe('web-paste-dialog-title')
    expect(dialog.getAttribute('aria-describedby')).toBe('web-paste-dialog-description')
    expect(dialog.querySelector('.web-paste-url-input')?.value).toBe('https://example.com/source')
    expect(dialog.querySelector('.web-paste-title-input')?.value).toBe('Example source')

    dialog.querySelector('[data-action="skip"]')?.dispatchEvent(new MouseEvent('click', { bubbles: true }))

    await expect(resultPromise).resolves.toEqual({ action: 'skip', metadata: undefined })
    expect(dialog.open).toBe(false)
  })

  it('resolves the image paste prompt as cancel on platform close requests', async () => {
    const { promptImageFilename } = await import('../imagePasteDialog.js')

    const resultPromise = promptImageFilename('screenshot.png')
    const dialog = /** @type {HTMLDialogElement} */ (document.querySelector('.image-paste-dialog'))
    expect(dialog?.tagName).toBe('DIALOG')
    expect(dialog.open).toBe(true)
    expect(dialog.getAttribute('aria-labelledby')).toBe('image-paste-dialog-title')
    expect(dialog.getAttribute('aria-describedby')).toBe('image-paste-dialog-description')
    expect(dialog.querySelector('.image-paste-filename-input')?.value).toBe('screenshot.png')

    dialog.dispatchEvent(new Event('cancel', { cancelable: true }))

    await expect(resultPromise).resolves.toEqual({ action: 'cancel', filename: undefined })
    expect(dialog.open).toBe(false)
  })
})

function installDialogPolyfill() {
  const proto = window.HTMLDialogElement?.prototype ?? Object.getPrototypeOf(document.createElement('dialog'))

  if (!proto.showModal) {
    proto.showModal = function showModal() {
      this.open = true
      this.setAttribute('open', '')
    }
  }

  if (!proto.close) {
    proto.close = function close(returnValue = '') {
      this.returnValue = returnValue
      this.open = false
      this.removeAttribute('open')
      this.dispatchEvent(new Event('close'))
    }
  }
}
