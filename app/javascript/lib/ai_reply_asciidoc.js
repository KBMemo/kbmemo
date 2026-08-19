function stripCodeFence(text) {
  return String(text ?? "")
    .trim()
    .replace(/^```(?:json|markdown|md|asciidoc|adoc)?\s*/i, "")
    .replace(/```\s*$/, "")
    .trim()
}

function unescapeJsonString(value) {
  return String(value ?? "")
    .replace(/\\n/g, "\n")
    .replace(/\\t/g, "\t")
    .replace(/\\r/g, "\r")
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, "\\")
}

function repairJsonStrings(text) {
  let out = ""
  let inString = false
  let escape = false
  for (const ch of String(text ?? "")) {
    if (!inString) {
      out += ch
      if (ch === '"') inString = true
      continue
    }

    if (escape) {
      out += ch
      escape = false
      continue
    }
    if (ch === "\\") {
      out += ch
      escape = true
      continue
    }
    if (ch === '"') {
      out += ch
      inString = false
      continue
    }
    if (ch === "\n") {
      out += "\\n"
      continue
    }
    if (ch === "\r") continue
    if (ch === "\t") {
      out += "\\t"
      continue
    }
    out += ch
  }
  return out
}

function tryParseJson(candidate) {
  try {
    return JSON.parse(candidate)
  } catch {
    const match = candidate.match(/\{[\s\S]*\}/)
    if (!match) return null
    try {
      return JSON.parse(match[0])
    } catch {
      try {
        return JSON.parse(repairJsonStrings(match[0]))
      } catch {
        return null
      }
    }
  }
}

function looksLikeJsonEnvelope(text) {
  const value = String(text ?? "").trim()
  return value.startsWith("{") && /"(?:reply|edit)"\s*:/.test(value) && /"edit"\s*:/.test(value)
}

function extractBrokenReply(text) {
  const match = String(text ?? "").match(/"reply"\s*:\s*"((?:\\.|[^"\\])*)"/)
  return match ? unescapeJsonString(match[1]).trim() : ""
}

function extractBrokenContent(text) {
  const value = String(text ?? "")
  const closed = value.match(/"content"\s*:\s*"([\s\S]*)"\s*\}\s*\}\s*$/)
  if (closed) return unescapeJsonString(closed[1]).trim()

  const open = /"content"\s*:\s*"/.exec(value)
  if (!open) return ""
  return unescapeJsonString(
    value.slice(open.index + open[0].length).replace(/"\s*\}[\s\}]*$/, "")
  ).trim()
}

function synthesizeBrokenEnvelope(text) {
  if (!looksLikeJsonEnvelope(text)) return null
  const content = extractBrokenContent(text)
  const reply = extractBrokenReply(text)
  if (!content && !reply) return null

  const targetMatch = text.match(/"target"\s*:\s*"(none|selection|unit|section|body)"/)
  return {
    reply,
    edit: {
      target: targetMatch?.[1] || "none",
      content
    }
  }
}

function parseJsonObject(raw) {
  const text = stripCodeFence(raw)
  if (!text) return null
  const start = text.indexOf("{")
  if (start < 0) return null

  const candidate = text.slice(start)
  return tryParseJson(candidate)
    || tryParseJson(repairJsonStrings(candidate))
    || synthesizeBrokenEnvelope(candidate)
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
  const parsed = parseJsonObject(fromEdit) || parseJsonObject(text)
  if (schemaPayload(parsed)) {
    const nested = String(parsed.edit?.content ?? "").trim()
    if (nested && !jsonEnvelope(nested)) return markdownToAsciidocLite(nested)
    const nestedReply = String(parsed.reply ?? "").trim()
    if (nestedReply && !jsonEnvelope(nestedReply)) return markdownToAsciidocLite(nestedReply)
    return ""
  }

  if (!jsonEnvelope(text) && !looksLikeJsonEnvelope(text)) return markdownToAsciidocLite(text)
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
