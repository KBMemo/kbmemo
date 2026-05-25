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
    tokens: ["--kb-memo-body-bg", "--kb-memo-body-text", "--kb-memo-body-border"],
    properties: {
      "background-color": "--kb-memo-body-bg",
      color: "--kb-memo-body-text",
      "border-color": "--kb-memo-body-border",
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
