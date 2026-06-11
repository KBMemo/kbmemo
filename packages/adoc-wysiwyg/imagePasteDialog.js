/** @typedef {'upload' | 'cancel'} ImagePasteDialogResult */

/** @type {HTMLDialogElement | null} */
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

    openDialog()
    requestAnimationFrame(() => {
      filenameInput.focus()
      filenameInput.select()
    })
  })
}

function ensureDialog() {
  if (dialogEl) return

  dialogEl = document.createElement('dialog')
  dialogEl.className = 'image-paste-dialog'
  dialogEl.setAttribute('closedby', 'any')
  dialogEl.setAttribute('aria-labelledby', 'image-paste-dialog-title')
  dialogEl.setAttribute('aria-describedby', 'image-paste-dialog-description')
  dialogEl.append(buildDialogForm())
  document.body.append(dialogEl)

  const form = /** @type {HTMLFormElement} */ (dialogEl.querySelector('.image-paste-form'))
  const filenameInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.image-paste-filename-input'))

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

    if (target === dialogEl && isBackdropClick(event)) {
      event.preventDefault()
      finishDialog('cancel')
      return
    }

    if (target.matches('[data-action="cancel"], .image-paste-close')) {
      event.preventDefault()
      finishDialog('cancel')
    }
  })

  dialogEl.addEventListener('cancel', (event) => {
    event.preventDefault()
    finishDialog('cancel')
  })

  dialogEl.addEventListener('close', () => {
    if (pendingResolve) finishDialog('cancel')
  })
}

function openDialog() {
  if (!dialogEl) return

  if (typeof dialogEl.showModal === 'function') {
    if (!dialogEl.open) dialogEl.showModal()
  } else {
    dialogEl.setAttribute('open', '')
  }
}

function buildDialogForm() {
  const form = document.createElement('form')
  form.className = 'image-paste-form'

  const header = document.createElement('div')
  header.className = 'image-paste-header'

  const headingGroup = document.createElement('div')
  const heading = document.createElement('strong')
  heading.id = 'image-paste-dialog-title'
  heading.textContent = '画像を貼り付け'
  const description = document.createElement('p')
  description.id = 'image-paste-dialog-description'
  description.className = 'image-paste-description'
  description.textContent = '保存するファイル名を指定してください。'
  headingGroup.append(heading, description)

  const closeButton = document.createElement('button')
  closeButton.type = 'button'
  closeButton.className = 'image-paste-close'
  closeButton.setAttribute('aria-label', '閉じる')
  closeButton.textContent = '×'
  header.append(headingGroup, closeButton)

  const field = document.createElement('label')
  field.className = 'image-paste-field'
  const labelText = document.createElement('span')
  labelText.textContent = 'ファイル名'
  const input = document.createElement('input')
  input.type = 'text'
  input.className = 'image-paste-filename-input'
  input.autocomplete = 'off'
  input.spellcheck = false
  input.placeholder = 'screenshot.png'
  input.required = true
  field.append(labelText, input)

  const actions = document.createElement('div')
  actions.className = 'image-paste-actions'
  actions.append(
    buildActionButton('submit', 'upload', '挿入'),
    buildActionButton('button', 'cancel', 'キャンセル'),
  )

  form.append(header, field, actions)
  return form
}

function buildActionButton(type, action, label) {
  const button = document.createElement('button')
  button.type = type
  button.dataset.action = action
  button.textContent = label
  return button
}

/**
 * @param {MouseEvent} event
 */
function isBackdropClick(event) {
  if (!dialogEl) return false

  const rect = dialogEl.getBoundingClientRect()
  return (
    event.clientY < rect.top ||
    event.clientY > rect.bottom ||
    event.clientX < rect.left ||
    event.clientX > rect.right
  )
}

/**
 * @param {ImagePasteDialogResult} action
 * @param {string} [filename]
 */
function finishDialog(action, filename) {
  if (!dialogEl || !pendingResolve) return

  const resolve = pendingResolve
  pendingResolve = null
  if (dialogEl.open && typeof dialogEl.close === 'function') {
    dialogEl.close(action)
  } else {
    dialogEl.removeAttribute('open')
  }
  resolve(action, filename)
}
