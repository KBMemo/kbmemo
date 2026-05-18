import { StreamLanguage } from "@codemirror/language"

const DIRECTIVE = /^@(start|end)[\w]*/

const KEYWORD =
  /^(?:skinparam|title|class|interface|enum|package|namespace|participant|actor|boundary|control|entity|database|queue|collections|note|abstract|annotation|artifact|agent|card|cloud|component|folder|frame|node|rectangle|state|usecase|alt|else|endif|end|loop|group|par|break|critical|fork|split|detach|kill|destroy|create|activate|deactivate|autonumber|return|ref|box|legend|left|right|center|of|as|is|on|off|hide|show|together|page|new|start|stop|repeat|while|endwhile|if|then|endif)\b/i

// よく使う矢印・関係線（完全網羅ではない）
const ARROW =
  /^(?:<-?|--?>|==?>|<[-=]+|--|\.\.?>?|<->|<-->|<-->|o{1,2}-?>|->>|<<-|<\|-|\|-?>|\*[-=]?>?|:>|\|>|\\|\|\|)/

const STEREOTYPE = /^<<[^>]*>>/

const QUOTED_STRING = /^"[^"]*"|^'[^']*'/

const HEX_COLOR = /^#[0-9a-fA-F]{3,8}\b/

const ACTIVITY_LABEL = /^:[^:\n;]+;/

const IDENTIFIER = /^[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*/

function token(stream) {
  if (stream.eatSpace()) return null

  if (stream.match(/'/)) {
    stream.skipToEnd()
    return "comment"
  }

  if (stream.match(DIRECTIVE)) return "meta"

  if (stream.match(HEX_COLOR)) return "atom"

  if (stream.match(QUOTED_STRING)) return "string"

  if (stream.match(STEREOTYPE)) return "qualifier"

  if (stream.match(KEYWORD)) return "keyword"

  if (stream.match(ARROW)) return "operator"

  if (stream.match(ACTIVITY_LABEL)) return "def"

  if (stream.match(IDENTIFIER)) return "variable"

  stream.next()
  return null
}

export const plantumlLanguage = StreamLanguage.define({
  name: "plantuml",
  token,
  languageData: {
    commentTokens: { line: "'" }
  }
})
