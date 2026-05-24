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
  dialogEl.innerHTML = `
    <form class="web-paste-form">
      <div class="web-paste-header">
        <div>
          <strong>Web から貼り付け</strong>
          <p class="web-paste-description">出典 URL があれば引用元リンクを末尾に追加します。</p>
        </div>
        <button type="button" class="web-paste-close" aria-label="閉じる">×</button>
      </div>
      <label class="web-paste-field">
        <span>出典 URL</span>
        <input type="url" class="web-paste-url-input" inputmode="url" autocomplete="off" spellcheck="false" placeholder="https://example.com/page" />
      </label>
      <label class="web-paste-field">
        <span>ページタイトル（任意）</span>
        <input type="text" class="web-paste-title-input" autocomplete="off" spellcheck="false" placeholder="記事タイトル" />
      </label>
      <div class="web-paste-actions">
        <button type="submit" data-action="paste">貼り付け</button>
        <button type="button" data-action="skip">出典なしで貼り付け</button>
        <button type="button" data-action="cancel">プレーンテキストで貼り付け</button>
      </div>
    </form>
  `
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
