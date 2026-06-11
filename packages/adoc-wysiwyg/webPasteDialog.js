/** @typedef {'paste' | 'skip' | 'cancel'} WebPasteDialogResult */

/** @type {HTMLElement | null} */
let dialogEl = null

/** @type {((result: WebPasteDialogResult, metadata?: { url?: string, title?: string }) => void) | null} */
let pendingResolve = null

/**
 * @param {{ title?: string, url?: string }} [defaults]
 * @returns {Promise<{ action: WebPasteDialogResult, metadata?: { url?: string, title?: string } }>}
 */
export function promptWebPasteSource(defaults = {}) {
  ensureDialog()

  return new Promise((resolve) => {
    if (pendingResolve) {
      pendingResolve('cancel')
    }
    pendingResolve = (action, metadata) => resolve({ action, metadata })

    const titleInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.web-paste-title-input'))
    const urlInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.web-paste-url-input'))
    titleInput.value = defaults.title ?? ''
    urlInput.value = defaults.url ?? ''

    dialogEl.hidden = false
    urlInput.focus()
    urlInput.select()
  })
}

function ensureDialog() {
  if (dialogEl) return

  dialogEl = document.createElement('div')
  dialogEl.className = 'web-paste-dialog'
  dialogEl.hidden = true
  dialogEl.append(buildDialogForm())
  document.body.append(dialogEl)

  const form = /** @type {HTMLFormElement} */ (dialogEl.querySelector('.web-paste-form'))
  const titleInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.web-paste-title-input'))
  const urlInput = /** @type {HTMLInputElement} */ (dialogEl.querySelector('.web-paste-url-input'))
  const closeButton = /** @type {HTMLButtonElement} */ (dialogEl.querySelector('.web-paste-close'))

  form.addEventListener('submit', (event) => {
    event.preventDefault()
    finishDialog('paste', readDialogMetadata(titleInput, urlInput))
  })

  dialogEl.addEventListener('click', (event) => {
    const target = event.target
    if (!(target instanceof HTMLElement)) return

    if (target.matches('[data-action="skip"]')) {
      event.preventDefault()
      finishDialog('skip')
      return
    }

    if (target.matches('[data-action="cancel"], .web-paste-close')) {
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

function buildDialogForm() {
  const form = document.createElement('form')
  form.className = 'web-paste-form'

  const header = document.createElement('div')
  header.className = 'web-paste-header'

  const headingGroup = document.createElement('div')
  const heading = document.createElement('strong')
  heading.textContent = 'Web から貼り付け'
  const description = document.createElement('p')
  description.className = 'web-paste-description'
  description.textContent = '出典 URL があれば引用元リンクを末尾に追加します。'
  headingGroup.append(heading, description)

  const closeButton = document.createElement('button')
  closeButton.type = 'button'
  closeButton.className = 'web-paste-close'
  closeButton.setAttribute('aria-label', '閉じる')
  closeButton.textContent = '×'
  header.append(headingGroup, closeButton)

  const urlField = buildTextField({
    className: 'web-paste-field',
    label: '出典 URL',
    inputClassName: 'web-paste-url-input',
    type: 'url',
    placeholder: 'https://example.com/page',
    inputMode: 'url',
  })
  const titleField = buildTextField({
    className: 'web-paste-field',
    label: 'ページタイトル（任意）',
    inputClassName: 'web-paste-title-input',
    type: 'text',
    placeholder: '記事タイトル',
  })

  const actions = document.createElement('div')
  actions.className = 'web-paste-actions'
  actions.append(
    buildActionButton('submit', 'paste', '貼り付け'),
    buildActionButton('button', 'skip', '出典なしで貼り付け'),
    buildActionButton('button', 'cancel', 'プレーンテキストで貼り付け'),
  )

  form.append(header, urlField, titleField, actions)
  return form
}

/**
 * @param {{ className: string, label: string, inputClassName: string, type: string, placeholder: string, inputMode?: string }} options
 */
function buildTextField({ className, label, inputClassName, type, placeholder, inputMode }) {
  const field = document.createElement('label')
  field.className = className

  const labelText = document.createElement('span')
  labelText.textContent = label

  const input = document.createElement('input')
  input.type = type
  input.className = inputClassName
  input.autocomplete = 'off'
  input.spellcheck = false
  input.placeholder = placeholder
  if (inputMode) input.inputMode = inputMode

  field.append(labelText, input)
  return field
}

function buildActionButton(type, action, label) {
  const button = document.createElement('button')
  button.type = type
  button.dataset.action = action
  button.textContent = label
  return button
}

/**
 * @param {HTMLInputElement} titleInput
 * @param {HTMLInputElement} urlInput
 */
function readDialogMetadata(titleInput, urlInput) {
  return {
    url: urlInput.value.trim(),
    title: titleInput.value.trim(),
  }
}

/**
 * @param {WebPasteDialogResult} action
 * @param {{ url?: string, title?: string }} [metadata]
 */
function finishDialog(action, metadata) {
  if (!dialogEl || !pendingResolve) return

  dialogEl.hidden = true
  const resolve = pendingResolve
  pendingResolve = null
  resolve(action, metadata)
}
