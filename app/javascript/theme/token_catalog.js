import { ADOC_TOKEN_META, allAdocTokenNames } from "./adoc_skin_tokens.js"

/** @type {Record<string, { label: string, group: "chrome" | "adoc" }>} */
export const KB_TOKEN_META = {
  "--kb-bg-page": { label: "ページ背景", group: "chrome" },
  "--kb-bg-surface": { label: "サーフェス", group: "chrome" },
  "--kb-bg-muted": { label: "Muted 背景", group: "chrome" },
  "--kb-bg-subtle": { label: "Subtle 背景", group: "chrome" },
  "--kb-text-primary": { label: "主要テキスト", group: "chrome" },
  "--kb-text-secondary": { label: "副次テキスト", group: "chrome" },
  "--kb-text-muted": { label: "Muted テキスト", group: "chrome" },
  "--kb-text-subtle": { label: "Subtle テキスト", group: "chrome" },
  "--kb-border": { label: "枠線", group: "chrome" },
  "--kb-border-strong": { label: "強調枠線", group: "chrome" },
  "--kb-accent": { label: "アクセント", group: "chrome" },
  "--kb-accent-hover": { label: "アクセント（ホバー）", group: "chrome" },
  "--kb-accent-fg": { label: "アクセント文字", group: "chrome" },
  "--kb-link": { label: "リンク", group: "chrome" },
  "--kb-link-hover": { label: "リンク（ホバー）", group: "chrome" },
  "--kb-memo-body-bg": { label: "メモ本文背景", group: "chrome" },
  "--kb-memo-body-text": { label: "メモ本文文字", group: "chrome" },
  "--kb-memo-body-border": { label: "メモ本文枠", group: "chrome" },
  "--kb-sidebar-bg": { label: "サイドバー背景", group: "chrome" },
  "--kb-editor-bg": { label: "エディタ背景", group: "chrome" },
  "--kb-kanban-column-bg": { label: "カンバン列", group: "chrome" },
  "--kb-kanban-card-bg": { label: "カンバンカード", group: "chrome" },
}

/** @type {{ id: "chrome" | "adoc" | "all", label: string }[]} */
export const TOKEN_GROUP_FILTERS = [
  { id: "all", label: "すべて" },
  { id: "chrome", label: "アプリ UI" },
  { id: "adoc", label: "AsciiDoc" },
]

/** @param {string} tokenName */
export function tokenMeta(tokenName) {
  if (KB_TOKEN_META[tokenName]) {
    return { ...KB_TOKEN_META[tokenName], name: tokenName }
  }
  if (ADOC_TOKEN_META[tokenName]) {
    return { label: ADOC_TOKEN_META[tokenName].label, group: "adoc", name: tokenName }
  }
  return { label: tokenName, group: tokenName.startsWith("--mg-") ? "adoc" : "chrome", name: tokenName }
}

/** @param {"all" | "chrome" | "adoc"} filter */
export function listTokenNames(filter = "all") {
  const names = new Set([...Object.keys(KB_TOKEN_META), ...allAdocTokenNames()])
  return Array.from(names)
    .filter((name) => {
      if (filter === "all") return true
      return tokenMeta(name).group === filter
    })
    .sort((a, b) => a.localeCompare(b))
}
