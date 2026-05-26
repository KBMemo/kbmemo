/** @type {Record<string, { label: string, tokens: string[], properties: Record<string, string> }>} */
export const THEME_SLOTS = {
  "app-body": {
    label: "ページ背景",
    tokens: ["--kb-bg-page", "--kb-text-primary"],
    properties: {
      "background-color": "--kb-bg-page",
      color: "--kb-text-primary",
    },
  },
  "app-header": {
    label: "ヘッダー",
    tokens: ["--kb-bg-surface", "--kb-border"],
    properties: {
      "background-color": "--kb-bg-surface",
      "border-color": "--kb-border",
    },
  },
  "memo-sidebar": {
    label: "メモサイドバー",
    tokens: ["--kb-sidebar-bg", "--kb-border"],
    properties: {
      "background-color": "--kb-sidebar-bg",
      "border-color": "--kb-border",
    },
  },
  "memo-title": {
    label: "メモタイトル",
    tokens: ["--kb-text-primary"],
    properties: {
      color: "--kb-text-primary",
    },
  },
  "memo-body": {
    label: "メモ本文",
    tokens: ["--kb-memo-body-bg", "--kb-memo-body-text", "--kb-memo-body-border", "--mg-text", "--mg-surface"],
    properties: {
      "background-color": "--kb-memo-body-bg",
      color: "--kb-memo-body-text",
      "border-color": "--kb-memo-body-border",
    },
  },
  "adoc-heading": {
    label: "AsciiDoc 見出し (h1–h3)",
    tokens: ["--mg-primary", "--mg-on-primary"],
    properties: {
      "background-color": "--mg-primary",
      color: "--mg-on-primary",
    },
  },
  "adoc-heading-sub": {
    label: "AsciiDoc 小見出し (h4–h6)",
    tokens: ["--mg-primary"],
    properties: {
      color: "--mg-primary",
    },
  },
  "adoc-link": {
    label: "AsciiDoc リンク",
    tokens: ["--mg-link", "--mg-link-hover"],
    properties: {
      color: "--mg-link",
    },
  },
  "adoc-code": {
    label: "AsciiDoc コード",
    tokens: ["--mg-code-bg", "--mg-text", "--mg-divider"],
    properties: {
      "background-color": "--mg-code-bg",
      color: "--mg-text",
      "border-color": "--mg-divider",
    },
  },
  "adoc-blockquote": {
    label: "AsciiDoc 引用",
    tokens: ["--mg-primary", "--mg-blockquote-bg", "--mg-text"],
    properties: {
      "border-color": "--mg-primary",
      "background-color": "--mg-blockquote-bg",
      color: "--mg-text",
    },
  },
  "adoc-admonition": {
    label: "AsciiDoc Admonition",
    tokens: ["--mg-tertiary", "--mg-primary", "--mg-secondary", "--mg-warning", "--mg-caution", "--mg-surface"],
    properties: {
      "background-color": "--mg-surface",
      "border-color": "--mg-border",
    },
  },
  "adoc-table": {
    label: "AsciiDoc 表",
    tokens: ["--mg-table-header-bg", "--mg-table-stripe-bg", "--mg-divider", "--mg-text"],
    properties: {
      "background-color": "--mg-table-header-bg",
      color: "--mg-text",
      "border-color": "--mg-divider",
    },
  },
  "memo-editor": {
    label: "メモエディタ",
    tokens: ["--kb-editor-bg", "--kb-border"],
    properties: {
      "background-color": "--kb-editor-bg",
      "border-color": "--kb-border",
    },
  },
  "kanban-column": {
    label: "カンバン列",
    tokens: ["--kb-kanban-column-bg", "--kb-border"],
    properties: {
      "background-color": "--kb-kanban-column-bg",
      "border-color": "--kb-border",
    },
  },
  "kanban-card": {
    label: "カンバンカード",
    tokens: ["--kb-kanban-card-bg", "--kb-text-primary", "--kb-border"],
    properties: {
      "background-color": "--kb-kanban-card-bg",
      color: "--kb-text-primary",
      "border-color": "--kb-border",
    },
  },
  "btn-primary": {
    label: "プライマリボタン",
    tokens: ["--kb-accent", "--kb-accent-fg", "--kb-accent-hover"],
    properties: {
      "background-color": "--kb-accent",
      color: "--kb-accent-fg",
    },
  },
}

/** @param {string} slot @param {string} property */
export function propertyToVariable(slot, property) {
  return THEME_SLOTS[slot]?.properties[property] ?? null
}

/** @param {string} slot */
export function slotLabel(slot) {
  return THEME_SLOTS[slot]?.label ?? slot
}

/** @returns {string[]} */
export function allThemeTokenNames() {
  const names = new Set()
  for (const slot of Object.values(THEME_SLOTS)) {
    for (const token of slot.tokens) names.add(token)
  }
  return Array.from(names).sort()
}
