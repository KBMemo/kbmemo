const trustedHTMLPolicies = new Map()

function trustedTypesApi() {
  return globalThis.trustedTypes
}

function trustedHTMLPolicy(policyName) {
  const api = trustedTypesApi()
  if (!api?.createPolicy) return null

  if (!trustedHTMLPolicies.has(policyName)) {
    trustedHTMLPolicies.set(
      policyName,
      api.createPolicy(policyName, {
        // Callers must pass only same-origin server HTML or server-sanitized markup.
        createHTML: (value) => String(value),
      })
    )
  }

  return trustedHTMLPolicies.get(policyName)
}

export function trustedHTML(policyName, html) {
  return trustedHTMLPolicy(policyName)?.createHTML(html) ?? html
}

export function setTrustedHTML(element, policyName, html) {
  element.innerHTML = trustedHTML(policyName, html)
}
