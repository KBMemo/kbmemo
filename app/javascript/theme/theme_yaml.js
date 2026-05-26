import { adocSkinsYamlToVariables, variablesToAdocSkinsYaml } from "./adoc_skin_tokens.js"

/** @typedef {import("./theme_storage.js").CustomTheme} CustomTheme */

/**
 * Minimal flat YAML parser for theme import (key: value lines, optional top-level blocks).
 * @param {string} text
 */
export function parseFlatYaml(text) {
  /** @type {Record<string, unknown>} */
  const root = {}
  /** @type {Record<string, unknown>} */
  let current = root
  /** @type {string | null} */
  let currentSection = null

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.replace(/\s+#.*$/, "").trimEnd()
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith("#")) continue

    const sectionMatch = trimmed.match(/^([A-Za-z0-9_-]+):\s*$/)
    if (sectionMatch) {
      currentSection = sectionMatch[1]
      root[currentSection] = root[currentSection] ?? {}
      current = /** @type {Record<string, unknown>} */ (root[currentSection])
      continue
    }

    const kvMatch = trimmed.match(/^([A-Za-z0-9_-]+):\s*(.+)$/)
    if (!kvMatch) continue

    const key = kvMatch[1]
    let value = kvMatch[2].trim()
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1)
    }

    if (currentSection) {
      current[key] = value
    } else {
      root[key] = value
    }
  }

  return root
}

/** @param {unknown} parsed */
export function themeFromImportPayload(parsed) {
  if (!parsed || typeof parsed !== "object") {
    throw new Error("Invalid theme payload")
  }

  const record = /** @type {Record<string, unknown>} */ (parsed)
  const themeRecord =
    record.theme && typeof record.theme === "object"
      ? /** @type {Record<string, unknown>} */ (record.theme)
      : record

  const label =
    typeof themeRecord.label === "string"
      ? themeRecord.label
      : typeof themeRecord.name === "string"
        ? themeRecord.name
        : "インポートしたテーマ"

  const baseTheme =
    typeof themeRecord.baseTheme === "string"
      ? themeRecord.baseTheme
      : typeof themeRecord.base === "string"
        ? themeRecord.base
        : "default"

  /** @type {Record<string, string>} */
  let variables = {}

  if (themeRecord.variables && typeof themeRecord.variables === "object") {
    variables = stringRecord(themeRecord.variables)
  }

  const chrome =
    themeRecord.chrome && typeof themeRecord.chrome === "object"
      ? stringRecord(themeRecord.chrome)
      : {}
  for (const [key, value] of Object.entries(chrome)) {
    const cssName = key.startsWith("--")
      ? key
      : `--kb-${key.replace(/_/g, "-")}`
    variables[cssName] = value
  }

  const adocBlock =
    themeRecord.asciidoctor_skins && typeof themeRecord.asciidoctor_skins === "object"
      ? stringRecord(themeRecord.asciidoctor_skins)
      : themeRecord.adoc && typeof themeRecord.adoc === "object"
        ? stringRecord(themeRecord.adoc)
        : null

  if (adocBlock) {
    variables = { ...variables, ...adocSkinsYamlToVariables(adocBlock) }
  } else {
    variables = { ...variables, ...adocSkinsYamlToVariables(stringRecord(themeRecord)) }
  }

  const rules = Array.isArray(themeRecord.rules) ? themeRecord.rules : []

  return {
    id: typeof themeRecord.id === "string" ? themeRecord.id : undefined,
    label,
    baseTheme,
    variables,
    rules,
  }
}

/** @param {string} text */
export function parseThemeImport(text) {
  const trimmed = text.trim()
  if (!trimmed) throw new Error("Empty import")

  if (trimmed.startsWith("{")) {
    return themeFromImportPayload(JSON.parse(trimmed))
  }

  return themeFromImportPayload(parseFlatYaml(trimmed))
}

/** @param {CustomTheme} theme */
export function exportThemeYaml(theme) {
  const adocYaml = variablesToAdocSkinsYaml(theme.variables)
  const chromeEntries = Object.entries(theme.variables)
    .filter(([name]) => name.startsWith("--kb-"))
    .sort(([a], [b]) => a.localeCompare(b))

  const lines = [
    "# kbmemo theme (asciidoctor-skins YAML compatible)",
    "kind: kbmemo-theme",
    "version: 1",
    `name: ${yamlQuote(theme.label)}`,
    `base: ${theme.baseTheme}`,
    "",
    "# asciidoctor-skins style palette",
    "asciidoctor_skins:",
  ]

  for (const [key, value] of Object.entries(adocYaml).sort(([a], [b]) => a.localeCompare(b))) {
    lines.push(`  ${key}: ${yamlQuote(value)}`)
  }

  if (chromeEntries.length > 0) {
    lines.push("", "# app chrome (--kb-*)", "chrome:")
    for (const [name, value] of chromeEntries) {
      const shortName = name.replace(/^--kb-/, "")
      lines.push(`  ${shortName}: ${yamlQuote(value)}`)
    }
  }

  if (theme.rules?.length) {
    lines.push("", "rules:", JSON.stringify(theme.rules, null, 2))
  }

  return `${lines.join("\n")}\n`
}

/** @param {unknown} value */
function stringRecord(value) {
  if (!value || typeof value !== "object") return {}
  return Object.fromEntries(
    Object.entries(value).filter(([, v]) => typeof v === "string")
  )
}

/** @param {string} value */
function yamlQuote(value) {
  if (/^[#A-Za-z0-9_.-]+$/.test(value)) return value
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`
}
