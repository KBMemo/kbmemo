/** @typedef {{ id: string, label: string, builtin: true }} BuiltinTheme */

/** @type {BuiltinTheme[]} */
export const BUILTIN_THEMES = [
  { id: "default", label: "Default", builtin: true },
  { id: "dark", label: "Dark", builtin: true },
  { id: "sepia", label: "Sepia", builtin: true },
  { id: "minimal", label: "Minimal", builtin: true },
]

/** @type {Record<string, Record<string, string>>} */
export const THEME_TOKEN_DEFAULTS = {
  default: {
    "--kb-bg-page": "#fafafa",
    "--kb-bg-surface": "#ffffff",
    "--kb-bg-muted": "#f4f4f5",
    "--kb-bg-subtle": "#fafafa",
    "--kb-text-primary": "#18181b",
    "--kb-text-secondary": "#52525b",
    "--kb-text-muted": "#71717a",
    "--kb-text-subtle": "#a1a1aa",
    "--kb-border": "#e4e4e7",
    "--kb-border-strong": "#d4d4d8",
    "--kb-accent": "#18181b",
    "--kb-accent-hover": "#27272a",
    "--kb-accent-fg": "#ffffff",
    "--kb-link": "#18181b",
    "--kb-link-hover": "#52525b",
    "--kb-memo-body-bg": "#ffffff",
    "--kb-memo-body-text": "#212121",
    "--kb-memo-body-border": "#e4e4e7",
    "--kb-sidebar-bg": "#ffffff",
    "--kb-editor-bg": "#ffffff",
    "--kb-kanban-column-bg": "#f4f4f5cc",
    "--kb-kanban-card-bg": "#ffffff",
  },
  dark: {
    "--kb-bg-page": "#0d1117",
    "--kb-bg-surface": "#161b22",
    "--kb-bg-muted": "#21262d",
    "--kb-bg-subtle": "#0d1117",
    "--kb-text-primary": "#e6edf3",
    "--kb-text-secondary": "#8b949e",
    "--kb-text-muted": "#6e7681",
    "--kb-text-subtle": "#484f58",
    "--kb-border": "#30363d",
    "--kb-border-strong": "#484f58",
    "--kb-accent": "#58a6ff",
    "--kb-accent-hover": "#79c0ff",
    "--kb-accent-fg": "#0d1117",
    "--kb-link": "#58a6ff",
    "--kb-link-hover": "#79c0ff",
    "--kb-memo-body-bg": "#0d1117",
    "--kb-memo-body-text": "#c9d1d9",
    "--kb-memo-body-border": "#30363d",
    "--kb-sidebar-bg": "#161b22",
    "--kb-editor-bg": "#161b22",
    "--kb-kanban-column-bg": "#21262dcc",
    "--kb-kanban-card-bg": "#161b22",
  },
  sepia: {
    "--kb-bg-page": "#f0e6d2",
    "--kb-bg-surface": "#f4ecd8",
    "--kb-bg-muted": "#ebe3d0",
    "--kb-bg-subtle": "#f0e6d2",
    "--kb-text-primary": "#2c2418",
    "--kb-text-secondary": "#5c4f3d",
    "--kb-text-muted": "#7a6a52",
    "--kb-text-subtle": "#a89880",
    "--kb-border": "#d4c4a8",
    "--kb-border-strong": "#c4b498",
    "--kb-accent": "#8b4513",
    "--kb-accent-hover": "#a0522d",
    "--kb-accent-fg": "#f4ecd8",
    "--kb-link": "#8b4513",
    "--kb-link-hover": "#a0522d",
    "--kb-memo-body-bg": "#f4ecd8",
    "--kb-memo-body-text": "#3d3428",
    "--kb-memo-body-border": "#d4c4a8",
    "--kb-sidebar-bg": "#f4ecd8",
    "--kb-editor-bg": "#f4ecd8",
    "--kb-kanban-column-bg": "#ebe3d0cc",
    "--kb-kanban-card-bg": "#f4ecd8",
  },
  minimal: {
    "--kb-bg-page": "#ffffff",
    "--kb-bg-surface": "#ffffff",
    "--kb-bg-muted": "#f6f6f6",
    "--kb-bg-subtle": "#fafafa",
    "--kb-text-primary": "#111111",
    "--kb-text-secondary": "#444444",
    "--kb-text-muted": "#666666",
    "--kb-text-subtle": "#999999",
    "--kb-border": "#dddddd",
    "--kb-border-strong": "#cccccc",
    "--kb-accent": "#111111",
    "--kb-accent-hover": "#333333",
    "--kb-accent-fg": "#ffffff",
    "--kb-link": "#222222",
    "--kb-link-hover": "#444444",
    "--kb-memo-body-bg": "#ffffff",
    "--kb-memo-body-text": "#222222",
    "--kb-memo-body-border": "#dddddd",
    "--kb-sidebar-bg": "#ffffff",
    "--kb-editor-bg": "#ffffff",
    "--kb-kanban-column-bg": "#f6f6f6cc",
    "--kb-kanban-card-bg": "#ffffff",
  },
}

/** @param {string} themeId */
export function getBuiltinTheme(themeId) {
  return BUILTIN_THEMES.find((theme) => theme.id === themeId) ?? BUILTIN_THEMES[0]
}

/** @param {string} themeId */
export function getThemeTokenDefaults(themeId) {
  return THEME_TOKEN_DEFAULTS[getBuiltinTheme(themeId).id]
}
