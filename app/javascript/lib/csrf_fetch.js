import { csrfFetchHeaders, getCsrfToken } from "@kbmemo/adoc-kbmemo"

export { getCsrfToken, csrfFetchHeaders }

export function jsonRequestHeaders() {
  return {
    Accept: "application/json",
    "Content-Type": "application/json",
    ...csrfFetchHeaders()
  }
}

export function withAuthenticityToken(payload) {
  const token = getCsrfToken()
  if (!token || payload == null || typeof payload !== "object") return payload

  return { ...payload, authenticity_token: token }
}

export function isCsrfErrorResponse(status, body) {
  return status === 422 && body?.code === "csrf_token_invalid"
}
