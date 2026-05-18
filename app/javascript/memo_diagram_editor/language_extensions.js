import { syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language"
import { plantumlLanguage } from "./plantuml_stream"

const highlight = syntaxHighlighting(defaultHighlightStyle, { fallback: true })

/**
 * @param {"mermaid"|"plantuml"|string} engine
 * @returns {Promise<import("@codemirror/state").Extension[]>}
 */
export async function diagramLanguageExtensions(engine) {
  if (engine === "mermaid") {
    const { mermaid } = await import("codemirror-lang-mermaid")
    return [mermaid(), highlight]
  }

  if (engine === "plantuml") {
    return [plantumlLanguage, highlight]
  }

  return []
}
