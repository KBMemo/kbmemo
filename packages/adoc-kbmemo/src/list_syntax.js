// codemirror-asciidoc listStart と同型（行頭マーカー + 空白）
export const LIST_LINE =
  /^(\s*)((?:\d+\.|[a-zA-Z]\.|[ixvmIXVM]+\)|\*{1,5}|-|\.{1,5}))(\s+)(.*)$/

const CHECKLIST_AFTER_MARKER = /^\[( |x|X|\*)\](\s*)(.*)$/

function listKind(marker) {
  if (/^\*+$/.test(marker) || marker === "-") return "bullet"
  return "ordered"
}

function listLevel(indent, marker) {
  const indentCols = indent.replace(/\t/g, "  ").length
  const indentLevel = Math.floor(indentCols / 2)
  if (/^\*+$/.test(marker)) return Math.min(5, indentLevel + marker.length)
  if (/^\.+$/.test(marker)) return Math.min(5, indentLevel + marker.length)
  return Math.min(5, indentLevel + 1)
}

export function parseListLine(text) {
  const match = text.match(LIST_LINE)
  if (!match) return null

  const indent = match[1]
  const marker = match[2]
  const space = match[3]
  let content = match[4]
  let checklistMarker = null

  const checklistMatch = content.match(CHECKLIST_AFTER_MARKER)
  if (checklistMatch) {
    checklistMarker = `[${checklistMatch[1]}]`
    content = checklistMatch[3] ?? ""
  }

  const markerEndInLine = indent.length + marker.length + space.length
  const kind = listKind(marker)
  const level = listLevel(indent, marker)

  return {
    indent,
    indentLength: indent.length,
    marker,
    markerEndInLine,
    content,
    checklistMarker,
    kind,
    level
  }
}

/** 同じインデント・同じマーカー形式の連続有序行の序数（1 始まり） */
export function orderedListIndex(doc, lineNo, indentLength, marker) {
  let index = 1
  for (let n = lineNo - 1; n >= 1; n--) {
    const prev = parseListLine(doc.line(n).text)
    if (!prev || prev.kind !== "ordered" || prev.indentLength !== indentLength) break
    if (prev.marker !== marker) break
    index++
  }
  return index
}

/** Enter で挿入する次行のマーカー */
export function listContinuationMarker(doc, lineNo, parsed) {
  const { marker, indentLength } = parsed
  if (/^\d+\.$/.test(marker)) {
    return `${orderedListIndex(doc, lineNo, indentLength, marker) + 1}.`
  }
  return marker
}

/** Enter で挿入する改行 + インデント + マーカー（チェックリストは [ ] を付与） */
export function listContinuationInsert(doc, lineNo, parsed) {
  const marker = listContinuationMarker(doc, lineNo, parsed)
  const checklist = parsed.checklistMarker ? " [ ] " : " "
  return `\n${parsed.indent}${marker}${checklist}`
}
