import { getActiveUnitIndex, getSourceOffsetForLine, parseEditUnitsFromSource } from "@kbmemo/adoc-codemirror"

const HEADING_LINE = /^(=+)\s+\S/
const TABLE_DELIMITER = /^\|===/
const LIST_LINE = /^(?:\*+|\.+|-)\s+\S/
const DLIST_LINE = /\S.*::$/

/**
 * @param {string | null | undefined} line
 * @returns {number}
 */
export function headingLevel(line) {
  const match = String(line ?? "").trim().match(HEADING_LINE)
  return match ? match[1].length : 0
}

/**
 * @param {string} source
 * @param {number} offset
 * @returns {number} 0-based line
 */
export function cursorLineFromOffset(source, offset) {
  const text = String(source ?? "")
  const pos = Math.max(0, Math.min(Number(offset) || 0, text.length))
  return text.slice(0, pos).split("\n").length - 1
}

/**
 * @param {string | null | undefined} adoc
 * @returns {"table" | "list" | "heading" | "paragraph"}
 */
export function classifyUnitKind(adoc) {
  const lines = String(adoc ?? "")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
  if (lines.length === 0) return "paragraph"
  if (lines.some((line) => TABLE_DELIMITER.test(line))) return "table"
  if (HEADING_LINE.test(lines[0]) && lines.length === 1) return "heading"
  if (LIST_LINE.test(lines[0]) || DLIST_LINE.test(lines[0])) return "list"
  return "paragraph"
}

/**
 * Inclusive 0-based line range for the heading section that contains cursorLine.
 *
 * @param {string} source
 * @param {number} cursorLine
 * @returns {{ startLine: number, endLine: number, heading: string, level: number } | null}
 */
export function sectionRangeAtLine(source, cursorLine) {
  const lines = String(source ?? "").split("\n")
  if (lines.length === 0) return null

  const clamped = Math.max(0, Math.min(cursorLine, lines.length - 1))
  let start = -1
  let level = 0
  for (let index = clamped; index >= 0; index--) {
    const nextLevel = headingLevel(lines[index])
    if (nextLevel > 0) {
      start = index
      level = nextLevel
      break
    }
  }
  if (start < 0) return null

  let end = lines.length - 1
  for (let index = start + 1; index < lines.length; index++) {
    const nextLevel = headingLevel(lines[index])
    if (nextLevel > 0 && nextLevel <= level) {
      end = index - 1
      break
    }
  }

  return {
    startLine: start,
    endLine: end,
    heading: lines[start].trim(),
    level
  }
}

/**
 * @param {string} source
 * @param {number} cursorLine
 * @returns {Promise<{ startLine: number, endLine: number, adoc: string, kind: string } | null>}
 */
export async function unitRangeAtLine(source, cursorLine) {
  const units = await parseEditUnitsFromSource(String(source ?? ""))
  if (!Array.isArray(units) || units.length === 0) return null

  const index = getActiveUnitIndex(units, Math.max(0, cursorLine))
  const unit = units[index]
  if (!unit) return null

  return {
    startLine: unit.startLine,
    endLine: unit.endLine,
    adoc: unit.adoc,
    kind: classifyUnitKind(unit.adoc)
  }
}

/**
 * @param {string} source
 * @param {number} startLine inclusive, 0-based
 * @param {number} endLine inclusive, 0-based
 */
export function sliceLineRange(source, startLine, endLine) {
  const lines = String(source ?? "").split("\n")
  if (lines.length === 0) return ""
  const from = Math.max(0, startLine)
  const to = Math.min(endLine, lines.length - 1)
  if (to < from) return ""
  return lines.slice(from, to + 1).join("\n")
}

/**
 * @param {string} source
 * @param {number} startLine inclusive, 0-based
 * @param {number} endLine inclusive, 0-based
 * @param {string} content
 */
export function replaceLineRange(source, startLine, endLine, content) {
  const lines = String(source ?? "").split("\n")
  const from = Math.max(0, startLine)
  const to = Math.min(Math.max(endLine, from - 1), lines.length - 1)
  const replacement = replacementLines(content)
  const prefix = lines.slice(0, from)
  const suffix = to >= 0 ? lines.slice(to + 1) : lines.slice(from)
  return [...prefix, ...replacement, ...suffix].join("\n")
}

/**
 * Character offsets for an inclusive line range, suitable for a CodeMirror change.
 *
 * @param {string} source
 * @param {number} startLine
 * @param {number} endLine
 * @returns {{ from: number, to: number }}
 */
export function lineRangeOffsets(source, startLine, endLine) {
  const text = String(source ?? "")
  const lines = text.split("\n")
  const fromLine = Math.max(0, startLine)
  const toLine = Math.min(endLine, Math.max(0, lines.length - 1))
  const from = getSourceOffsetForLine(text, fromLine)
  if (toLine >= lines.length - 1) return { from, to: text.length }
  return { from, to: getSourceOffsetForLine(text, toLine + 1) }
}

function replacementLines(content) {
  const text = String(content ?? "")
  if (text === "") return []
  return text.replace(/\n$/, "").split("\n")
}
