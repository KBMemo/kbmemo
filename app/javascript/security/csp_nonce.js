export function getCspNonce() {
  const element = document.querySelector('meta[name="csp-nonce"]')
  return element?.nonce || element?.content || ""
}

export function codeMirrorCspNonceExtension(EditorView) {
  const nonce = getCspNonce()
  return nonce ? EditorView.cspNonce.of(nonce) : []
}
