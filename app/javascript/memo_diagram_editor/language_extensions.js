import { syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language"

/**
 * @param {"mermaid"|"plantuml"|string} engine
 * @returns {Promise<import("@codemirror/state").Extension[]>}
 */
export async function diagramLanguageExtensions(engine) {
  if (engine === "mermaid") {
    const { mermaid } = await import("codemirror-lang-mermaid")
    return [mermaid(), syntaxHighlighting(defaultHighlightStyle, { fallback: true })]
  }

  // PlantUML: 公式 CM6 言語パッケージなし（PR-C で強化予定）
  return []
}
