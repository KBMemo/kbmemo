function stripCodeFence(text) {
  return String(text ?? "")
    .trim()
    .replace(/^```(?:json|markdown|md|asciidoc|adoc)?\s*/i, "")
    .replace(/```\s*$/, "")
    .trim()
}

function parseJsonObject(raw) {
  const text = stripCodeFence(raw)
  if (!text) return null
  const start = text.indexOf("{")
  if (start < 0) return null

  const candidate = text.slice(start)
  try {
    return JSON.parse(candidate)
  } catch {
    const match = candidate.match(/\{[\s\S]*\}/)
    if (!match) return null
    try {
      return JSON.parse(match[0])
    } catch {
      return null
    }
  }
}

function schemaPayload(data) {
  return Boolean(data && typeof data === "object" && !Array.isArray(data) && ("reply" in data || "edit" in data))
}

export function jsonEnvelope(text) {
  return schemaPayload(parseJsonObject(text))
}

export function looksLikeMarkdown(text) {
  const value = String(text ?? "")
  if (!value.trim()) return false
  if (/\[[^\]]+\]\([^)\s]+\)/.test(value)) return true

  const lines = value.split("\n")
  const strong = lines.some((line) => (
    /^#{1,6}\s+\S/.test(line) ||
    /^\s*```/.test(line) ||
    /^\s*\|.*-{3,}/.test(line)
  ))
  if (strong) return true

  const hasAsciidocStructure = lines.some((line) => (
    /^=+\s+\S/.test(line) ||
    /^\s*\*\s+\S/.test(line) ||
    /^\|===/.test(line) ||
    /^\[source/.test(line)
  ))
  if (hasAsciidocStructure) return false

  return lines.some((line) => /^\s*[-+]\s+\S/.test(line) || /^\s*\d+\.\s+\S/.test(line))
}

export function markdownToAsciidocLite(text) {
  const source = String(text ?? "").replace(/\r\n/g, "\n")
  if (!looksLikeMarkdown(source)) return source.trim()

  let value = convertFencedCode(source)
  value = value.replace(/^######\s+/gm, "====== ")
  value = value.replace(/^#####\s+/gm, "===== ")
  value = value.replace(/^####\s+/gm, "==== ")
  value = value.replace(/^###\s+/gm, "=== ")
  value = value.replace(/^##\s+/gm, "== ")
  value = value.replace(/^#\s+/gm, "= ")
  value = value.replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, "$2[$1]")
  value = value.replace(/^(\s*)[-+]\s+/gm, "$1* ")
  value = value.replace(/^(\s*)\d+\.\s+/gm, "$1. ")
  value = value.replace(/\*\*(.+?)\*\*/g, "*$1*")
  return value.trim()
}

export function asciiDocFromAiReply(reply, edit = null) {
  const fromEdit = String(edit?.content ?? "").trim()
  if (fromEdit && !jsonEnvelope(fromEdit)) return markdownToAsciidocLite(fromEdit)

  const text = String(reply ?? "").trim()
  const parsed = parseJsonObject(text)
  if (schemaPayload(parsed)) {
    const nested = String(parsed.edit?.content ?? "").trim()
    if (nested && !jsonEnvelope(nested)) return markdownToAsciidocLite(nested)
    const nestedReply = String(parsed.reply ?? "").trim()
    if (nestedReply && !jsonEnvelope(nestedReply)) return markdownToAsciidocLite(nestedReply)
    return ""
  }

  if (!jsonEnvelope(text)) return markdownToAsciidocLite(text)
  return ""
}

function convertFencedCode(text) {
  return text.replace(/^```([^\n]*)\n([\s\S]*?)^```[ \t]*$/gm, (_match, lang, body) => {
    const language = String(lang ?? "").trim()
    const header = language ? `[source,${language}]` : "[source]"
    const source = String(body ?? "").replace(/\n$/, "")
    return `${header}\n----\n${source}\n----`
  })
}
