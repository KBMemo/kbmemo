import { RangeSet } from "@codemirror/state"
import { Decoration, EditorView, ViewPlugin, WidgetType } from "@codemirror/view"
import { codeBlockByLine, scanCodeBlocks } from "./code_block_syntax"
import {
  memoAssetSrc,
  parseBlockImageLine,
  scanImageMacrosOnLine
} from "./image_syntax"
import { scanTableBlocks, tableBlockByLine } from "./table_syntax"
import { getViewportLineRange, shouldDecorateEditorLine } from "./viewport_lazy"

function selectionTouches(state, from, to) {
  return state.selection.ranges.some((range) => {
    const start = Math.min(range.anchor, range.head)
    const end = Math.max(range.anchor, range.head)
    return start < to && end > from
  })
}

function cursorOnLine(state, line) {
  return state.selection.ranges.some((range) => state.doc.lineAt(range.head).number === line.number)
}

function pushSpec(specs, from, to, deco) {
  specs.push({ from, to, deco })
}

class ImagePreviewWidget extends WidgetType {
  constructor({ src, alt, block }) {
    super()
    this.src = src
    this.alt = alt
    this.block = block
  }

  eq(other) {
    return other.src === this.src && other.alt === this.alt && other.block === this.block
  }

  toDOM() {
    const wrap = document.createElement(this.block ? "figure" : "span")
    wrap.className = this.block
      ? "cm-wysiwyg-image cm-wysiwyg-image--block"
      : "cm-wysiwyg-image cm-wysiwyg-image--inline"

    if (!this.src) {
      const missing = document.createElement("span")
      missing.className = "cm-wysiwyg-image-missing"
      missing.textContent = this.alt
      wrap.appendChild(missing)
      return wrap
    }

    const img = document.createElement("img")
    img.src = this.src
    img.alt = this.alt
    img.className = "cm-wysiwyg-image-preview"
    img.loading = "lazy"
    img.decoding = "async"
    img.onerror = () => {
      img.remove()
      if (!wrap.querySelector(".cm-wysiwyg-image-missing")) {
        const missing = document.createElement("span")
        missing.className = "cm-wysiwyg-image-missing"
        missing.textContent = this.alt
        wrap.appendChild(missing)
      }
    }
    wrap.appendChild(img)
    return wrap
  }

  ignoreEvent() {
    return true
  }

  get estimatedHeight() {
    return this.block ? 200 : 56
  }
}

function buildImageDecorations(view, getMemoId) {
  const specs = []
  const atomicRanges = []
  const { state } = view
  const editingActive = view.hasFocus
  const memoId = getMemoId()

  const codeBlocks = scanCodeBlocks(state.doc)
  const codeByLine = codeBlockByLine(codeBlocks)
  const tableBlocks = scanTableBlocks(state.doc, (n) => codeByLine.has(n))
  const tableByLine = tableBlockByLine(tableBlocks)
  const viewportRange = getViewportLineRange(state)
  for (let lineNo = 1; lineNo <= state.doc.lines; lineNo++) {
    if (codeByLine.has(lineNo) || tableByLine.has(lineNo)) continue
    if (!shouldDecorateEditorLine(view, lineNo, viewportRange)) continue

    const line = state.doc.line(lineNo)
    const text = line.text
    const onLine = editingActive && cursorOnLine(state, line)

    const blockImage = parseBlockImageLine(text)
    if (blockImage && !onLine) {
      const src = memoAssetSrc(memoId, blockImage.filename)
      // block replace は ViewPlugin 不可（表と同様 StateField が必要）。行全体 replace で十分。
      pushSpec(
        specs,
        line.from,
        line.to,
        Decoration.replace({
          widget: new ImagePreviewWidget({ src, alt: blockImage.filename, block: true })
        })
      )
      atomicRanges.push({ from: line.from, to: line.to })
      continue
    }

    if (onLine) continue

    for (const macro of scanImageMacrosOnLine(text, line.from)) {
      if (macro.block && macro.from === line.from && macro.to === line.to) continue
      if (editingActive && selectionTouches(state, macro.from, macro.to)) continue

      const src = memoAssetSrc(memoId, macro.filename)
      pushSpec(
        specs,
        macro.from,
        macro.to,
        Decoration.replace({
          widget: new ImagePreviewWidget({
            src,
            alt: macro.filename,
            block: macro.block
          })
        })
      )
      atomicRanges.push({ from: macro.from, to: macro.to })
    }
  }

  const decorations = Decoration.set(
    specs.map((spec) => spec.deco.range(spec.from, spec.to)),
    true
  )

  const atomic =
    atomicRanges.length > 0
      ? RangeSet.of(
          atomicRanges.map((r) => Decoration.replace({}).range(r.from, r.to)),
          true
        )
      : RangeSet.empty

  return { decorations, atomicRanges: atomic }
}

/**
 * Phase 5f: `image::path[]` / `image:path[]` のインラインプレビュー。
 * カーソル行（ブロック行）またはマクロ選択中は生 AsciiDoc。
 */
export function imageWysiwygExtension(getMemoId) {
  const plugin = ViewPlugin.fromClass(
    class {
      constructor(view) {
        const built = buildImageDecorations(view, getMemoId)
        this.decorations = built.decorations
        this.atomicRanges = built.atomicRanges
      }

      update(update) {
        if (
          update.docChanged ||
          update.selectionSet ||
          update.viewportChanged ||
          update.focusChanged
        ) {
          const built = buildImageDecorations(update.view, getMemoId)
          this.decorations = built.decorations
          this.atomicRanges = built.atomicRanges
        }
      }
    },
    {
      decorations: (v) => v.decorations,
      provide: (plugin) =>
        EditorView.atomicRanges.of((view) => view.plugin(plugin)?.atomicRanges ?? RangeSet.empty)
    }
  )

  return plugin
}
