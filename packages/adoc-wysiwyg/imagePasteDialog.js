/** @typedef {'upload' | 'cancel'} ImagePasteDialogResult */

/** @type {HTMLElement | null} */
let dialogEl = null

/** @type {((result: ImagePasteDialogResult, filename?: string) => void) | null} */
let pendingResolve = null

/**
 * @param {string} defaultName
 * @returns {Promise<{ action: ImagePasteDialogResult, filename?: string }>}
 */
export function promptImageFilename(defaultName) {
  ensureDialog()

  return new Promise((resolve) => {
    if (pendingResolve) {
      pendingResolve('cancel')
    }
    pendingResolve = (action, filename) => resolve({ action, filename })

    const filenameInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.image-paste-filename-input'))
    filenameInput.value = defaultName

    dialogEl.hidden = false
    filenameInput.focus()
    filenameInput.select()
  })
}

function ensureDialog() {
  if (dialogEl) return

  dialogEl = document.createElement('div')
  dialogEl.className = 'image-paste-dialog'
  dialogEl.hidden = true
  dialogEl.innerHTML = `
    <form class="image-paste-form">
      <div class="image-paste-header">
        <div>
          <strong>画像を貼り付け</strong>
          <p class="image-paste-description">保存するファイル名を指定してください。</p>
        </div>
        <button type="button" class="image-paste-close" aria-label="閉じる">×</button>
      </div>
      <label class="image-paste-field">
        <span>ファイル名</span>
        <input type="text" class="image-paste-filename-input" autocomplete="off" spellcheck="false" placeholder="screenshot.png" required />
      </label>
      <div class="image-paste-actions">
        <button type="submit" data-action="upload">挿入</button>
        <button type="button" data-action="cancel">キャンセル</button>
      </div>
    </form>
  `
  document.body.append(dialogEl)

  const form = /** @type {HTMLFormElement} */ (dialogEl.querySelector('.image-paste-form'))
  const filenameInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.image-paste-filename-input'))
  const closeButton = /** @type {HTMLButtonElement} */ (dialogEl.querySelector('.image-paste-close'))

  form.addEventListener('submit', (event) => {
    event.preventDefault()
    const filename = filenameInput.value.trim()
    if (!filename) {
      filenameInput.focus()
      return
    }
    finishDialog('upload', filename)
  })

  dialogEl.addEventListener('click', (event) => {
    const target = event.target
    if (!(target instanceof HTMLElement)) return

    if (target.matches('[data-action="cancel"], .image-paste-close')) {
      event.preventDefault()
      finishDialog('cancel')
    }
  })

  closeButton.addEventListener('click', () => finishDialog('cancel'))

  document.addEventListener('keydown', (event) => {
    if (dialogEl?.hidden || !pendingResolve) return
    if (event.key === 'Escape') {
      event.preventDefault()
      finishDialog('cancel')
    }
  })
}

/**
 * @param {ImagePasteDialogResult} action
 * @param {string} [filename]
 */
function finishDialog(action, filename) {
  if (!dialogEl || !pendingResolve) return

  dialogEl.hidden = true
  const resolve = pendingResolve
  pendingResolve = null
  resolve(action, filename)
}
