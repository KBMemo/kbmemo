/** AsciiDoc skin tokens (--mg-*) aligned with asciidoctor-skins :root variables. */

/** @type {Record<string, string>} asciidoctor-skins YAML key → CSS variable */
export const ADOC_SKINS_YAML_MAP = {
  maincolor: "--mg-surface",
  primarycolor: "--mg-primary",
  secondarycolor: "--mg-secondary",
  tertiarycolor: "--mg-tertiary",
  sidebarbackground: "--mg-sidebar",
  linkcolor: "--mg-link",
  linkcoloralternate: "--mg-link-alt",
  white: "--mg-on-primary",
  black: "--mg-text-strong",
}

/** @type {Record<string, { label: string, yamlKey?: string }>} */
export const ADOC_TOKEN_META = {
  "--mg-primary": { label: "Primary（見出し・強調）", yamlKey: "primarycolor" },
  "--mg-secondary": { label: "Secondary（Important 等）", yamlKey: "secondarycolor" },
  "--mg-tertiary": { label: "Tertiary（Note 等）", yamlKey: "tertiarycolor" },
  "--mg-text": { label: "本文テキスト", yamlKey: "maincolor" },
  "--mg-surface": { label: "本文背景", yamlKey: "maincolor" },
  "--mg-border": { label: "枠線" },
  "--mg-divider": { label: "区切り線" },
  "--mg-link": { label: "リンク", yamlKey: "linkcolor" },
  "--mg-link-hover": { label: "リンク（ホバー）" },
  "--mg-link-alt": { label: "リンク（代替）", yamlKey: "linkcoloralternate" },
  "--mg-on-primary": { label: "Primary 上の文字", yamlKey: "white" },
  "--mg-warning": { label: "Warning" },
  "--mg-caution": { label: "Caution" },
  "--mg-blockquote-bg": { label: "引用背景" },
  "--mg-code-bg": { label: "コード背景" },
  "--mg-table-header-bg": { label: "表ヘッダー背景" },
  "--mg-table-stripe-bg": { label: "表ストライプ背景" },
  "--mg-sidebar": { label: "サイドバー背景", yamlKey: "sidebarbackground" },
}

/** @type {Record<string, Record<string, string>>} */
export const ADOC_TOKEN_DEFAULTS = {
  default: {
    "--mg-primary": "#9e9e9e",
    "--mg-secondary": "#ba3925",
    "--mg-tertiary": "#186d7a",
    "--mg-text": "#212121",
    "--mg-surface": "#ffffff",
    "--mg-border": "#bdbdbd",
    "--mg-divider": "#e0e0e0",
    "--mg-link": "#212121",
    "--mg-link-hover": "#9e9e9e",
    "--mg-link-alt": "#f44336",
    "--mg-on-primary": "#ffffff",
    "--mg-warning": "#bf6900",
    "--mg-caution": "#f44336",
    "--mg-blockquote-bg": "#f5f5f5",
    "--mg-code-bg": "#f7f7f8",
    "--mg-table-header-bg": "#eeeeee",
    "--mg-table-stripe-bg": "#fafafa",
    "--mg-sidebar": "#212121",
  },
  dark: {
    "--mg-primary": "#21262d",
    "--mg-secondary": "#ba3925",
    "--mg-tertiary": "#4db6ac",
    "--mg-text": "#c9d1d9",
    "--mg-surface": "#0d1117",
    "--mg-border": "#30363d",
    "--mg-divider": "#30363d",
    "--mg-link": "#58a6ff",
    "--mg-link-hover": "#79c0ff",
    "--mg-link-alt": "#ff9800",
    "--mg-on-primary": "#e6edf3",
    "--mg-warning": "#bf6900",
    "--mg-caution": "#f44336",
    "--mg-blockquote-bg": "#161b22",
    "--mg-code-bg": "#161b22",
    "--mg-table-header-bg": "#21262d",
    "--mg-table-stripe-bg": "#161b22",
    "--mg-sidebar": "#21252b",
  },
  sepia: {
    "--mg-primary": "#c4b498",
    "--mg-secondary": "#8b4513",
    "--mg-tertiary": "#7a6a52",
    "--mg-text": "#3d3428",
    "--mg-surface": "#f4ecd8",
    "--mg-border": "#d4c4a8",
    "--mg-divider": "#d4c4a8",
    "--mg-link": "#8b4513",
    "--mg-link-hover": "#a0522d",
    "--mg-link-alt": "#ba3925",
    "--mg-on-primary": "#2c2418",
    "--mg-warning": "#bf6900",
    "--mg-caution": "#f44336",
    "--mg-blockquote-bg": "#ebe3d0",
    "--mg-code-bg": "#ebe3d0",
    "--mg-table-header-bg": "#ebe3d0",
    "--mg-table-stripe-bg": "#f0e6d2",
    "--mg-sidebar": "#5c4f3d",
  },
  minimal: {
    "--mg-primary": "#111111",
    "--mg-secondary": "#444444",
    "--mg-tertiary": "#666666",
    "--mg-text": "#222222",
    "--mg-surface": "#ffffff",
    "--mg-border": "#dddddd",
    "--mg-divider": "#dddddd",
    "--mg-link": "#222222",
    "--mg-link-hover": "#444444",
    "--mg-link-alt": "#666666",
    "--mg-on-primary": "#ffffff",
    "--mg-warning": "#bf6900",
    "--mg-caution": "#f44336",
    "--mg-blockquote-bg": "#f6f6f6",
    "--mg-code-bg": "#f6f6f6",
    "--mg-table-header-bg": "#f6f6f6",
    "--mg-table-stripe-bg": "#fafafa",
    "--mg-sidebar": "#fafafa",
  },
}

/** @param {string} baseThemeId */
export function getAdocTokenDefaults(baseThemeId) {
  return ADOC_TOKEN_DEFAULTS[baseThemeId] ?? ADOC_TOKEN_DEFAULTS.default
}

/** @returns {string[]} */
export function allAdocTokenNames() {
  return Object.keys(ADOC_TOKEN_META)
}

/** @param {Record<string, string>} yaml */
export function adocSkinsYamlToVariables(yaml) {
  /** @type {Record<string, string>} */
  const variables = {}

  for (const [key, value] of Object.entries(yaml)) {
    if (typeof value !== "string") continue
    const normalized = key.trim().toLowerCase()
    const cssVar = ADOC_SKINS_YAML_MAP[normalized]
    if (cssVar) variables[cssVar] = value.trim()
  }

  if (variables["--mg-on-primary"] && !variables["--mg-text"]) {
    variables["--mg-text"] = variables["--mg-on-primary"]
  }

  return variables
}

/** @param {Record<string, string>} variables */
export function variablesToAdocSkinsYaml(variables) {
  /** @type {Record<string, string>} */
  const yaml = {}
  const reverse = Object.fromEntries(
    Object.entries(ADOC_SKINS_YAML_MAP).map(([yamlKey, cssVar]) => [cssVar, yamlKey])
  )

  for (const [cssVar, meta] of Object.entries(ADOC_TOKEN_META)) {
    const value = variables[cssVar]
    if (!value) continue
    const yamlKey = meta.yamlKey ?? reverse[cssVar]
    if (yamlKey) yaml[yamlKey] = value
  }

  return yaml
}
