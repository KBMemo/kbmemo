import { describe, expect, it } from "vitest"
import {
  classifyUnitKind,
  cursorLineFromOffset,
  headingLevel,
  lineRangeOffsets,
  replaceLineRange,
  sectionRangeAtLine,
  sliceLineRange,
  unitRangeAtLine
} from "../adoc_edit_targets.js"

const SAMPLE = [
  "= Doc",
  "",
  "intro",
  "",
  "== Alpha",
  "aaa",
  "",
  "=== Nested",
  "nested body",
  "",
  "== Beta",
  "bbb"
].join("\n")

describe("adoc_edit_targets", () => {
  it("reads heading levels", () => {
    expect(headingLevel("== Alpha")).toBe(2)
    expect(headingLevel("intro")).toBe(0)
  })

  it("maps a cursor offset to a line", () => {
    expect(cursorLineFromOffset("a\nbc\nd", 0)).toBe(0)
    expect(cursorLineFromOffset("a\nbc\nd", 2)).toBe(1)
    expect(cursorLineFromOffset("a\nbc\nd", 7)).toBe(2)
  })

  it("classifies list table heading and paragraph units", () => {
    expect(classifyUnitKind("* one\n* two")).toBe("list")
    expect(classifyUnitKind(". one\n. two")).toBe("list")
    expect(classifyUnitKind("|===\n| a | b\n|===")).toBe("table")
    expect(classifyUnitKind("== Heading")).toBe("heading")
    expect(classifyUnitKind("a paragraph")).toBe("paragraph")
  })

  it("finds the current section including nested headings", () => {
    const nested = sectionRangeAtLine(SAMPLE, 8)
    expect(nested).toMatchObject({ startLine: 7, endLine: 9, heading: "=== Nested", level: 3 })
    expect(sliceLineRange(SAMPLE, nested.startLine, nested.endLine)).toContain("nested body")

    const alpha = sectionRangeAtLine(SAMPLE, 5)
    expect(alpha).toMatchObject({ startLine: 4, heading: "== Alpha", level: 2 })
    expect(alpha.endLine).toBe(9)

    const beta = sectionRangeAtLine(SAMPLE, 11)
    expect(beta).toMatchObject({ startLine: 10, endLine: 11, heading: "== Beta" })
  })

  it("replaces an inclusive line range", () => {
    expect(replaceLineRange("a\nb\nc", 1, 1, "B")).toBe("a\nB\nc")
    expect(replaceLineRange("a\nb\nc", 1, 2, "B\nC\n")).toBe("a\nB\nC")
    expect(replaceLineRange("a\nb\nc", 0, 2, "X")).toBe("X")
  })

  it("converts a line range to character offsets", () => {
    expect(lineRangeOffsets("a\nbc\nd", 1, 1)).toEqual({ from: 2, to: 5 })
    expect(lineRangeOffsets("a\nbc\nd", 1, 2)).toEqual({ from: 2, to: 6 })
  })

  it("finds the list or table unit at the cursor", async () => {
    const listSource = "= Title\n\n* one\n* two\n\npara"
    const list = await unitRangeAtLine(listSource, 2)
    expect(list?.kind).toBe("list")
    expect(list?.adoc).toContain("* one")

    const tableSource = "= Title\n\n|===\n| a | b\n|===\n"
    const table = await unitRangeAtLine(tableSource, 3)
    expect(table?.kind).toBe("table")
    expect(table?.adoc).toContain("|===")
  })
})
