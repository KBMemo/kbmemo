const DEFAULT_POLICY_NAME = "default"

export function installDefaultTrustedTypesPolicy() {
  const api = globalThis.trustedTypes
  if (!api?.createPolicy) return null

  try {
    return api.createPolicy(DEFAULT_POLICY_NAME, {
      // Turbo parses same-origin server-rendered HTML and activates its scripts.
      createHTML: (value) => String(value),
      createScript: (value) => String(value),
    })
  } catch (error) {
    if (error instanceof TypeError) return null
    throw error
  }
}

installDefaultTrustedTypesPolicy()
