const trustedHTMLPolicies = new Map()

function trustedHTMLPolicy(policyName) {
  const api = globalThis.trustedTypes
  if (!api?.createPolicy) return null

  if (!trustedHTMLPolicies.has(policyName)) {
    trustedHTMLPolicies.set(
      policyName,
      api.createPolicy(policyName, {
        // Callers must pass only escaped text, preserved callout markup, or highlight.js output.
        createHTML: (value) => String(value),
      })
    )
  }

  return trustedHTMLPolicies.get(policyName)
}

export function setTrustedHTML(element, policyName, html) {
  element.innerHTML = trustedHTMLPolicy(policyName)?.createHTML(html) ?? html
}
