const FORM_CONTROL_SELECTOR = "input:not([type='hidden']), textarea, select"
const CLIENT_INVALID_ATTR = "data-kb-client-invalid"
let initialized = false

function supportsUserInvalid() {
  try {
    return window.CSS?.supports?.("selector(:user-invalid)") === true
  } catch {
    return false
  }
}

function formControlFromEvent(event) {
  const target = event.target
  return target?.matches?.(FORM_CONTROL_SELECTOR) ? target : null
}

function setClientInvalid(control) {
  control.setAttribute("aria-invalid", "true")
  control.setAttribute(CLIENT_INVALID_ATTR, "true")
}

function clearClientInvalid(control) {
  if (!control.hasAttribute(CLIENT_INVALID_ATTR)) return

  control.removeAttribute("aria-invalid")
  control.removeAttribute(CLIENT_INVALID_ATTR)
}

function syncControlAria(control) {
  if (control.matches(":user-invalid")) {
    setClientInvalid(control)
  } else {
    clearClientInvalid(control)
  }
}

function syncControlFromEvent(event) {
  const control = formControlFromEvent(event)
  if (!control) return

  syncControlAria(control)
}

function clearFormClientInvalid(event) {
  const form = event.target
  if (!form?.matches?.("form")) return

  form.querySelectorAll(`[${CLIENT_INVALID_ATTR}]`).forEach((control) => {
    clearClientInvalid(control)
  })
}

export function initUserInvalidAriaSync() {
  if (initialized) return
  if (!supportsUserInvalid()) return

  initialized = true
  document.addEventListener("blur", syncControlFromEvent, true)
  document.addEventListener("invalid", syncControlFromEvent, true)
  document.addEventListener("reset", clearFormClientInvalid, true)
  document.addEventListener("input", (event) => {
    const control = formControlFromEvent(event)
    if (!control?.hasAttribute(CLIENT_INVALID_ATTR)) return

    syncControlAria(control)
  })
  document.addEventListener("change", (event) => {
    const control = formControlFromEvent(event)
    if (!control?.hasAttribute(CLIENT_INVALID_ATTR)) return

    syncControlAria(control)
  })
}
