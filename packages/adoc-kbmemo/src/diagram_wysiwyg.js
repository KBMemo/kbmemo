import { RangeSet } from '@codemirror/state'
import { Decoration, EditorView, ViewPlugin, WidgetType } from '@codemirror/view'
import { codeBlockByLine, scanCodeBlocks } from './code_block_syntax'
import {
  diagramEditUrl,
  diagramSourceUrl,
  diagramSvgRelativePath,
  diagramViewUrl,
  parseBlockDiagramLine,
  scanDiagramMacrosOnLine,
} from './diagram_syntax'
import { memoAssetSrc } from './image_syntax'
import { scanTableBlocks, tableBlockByLine } from './table_syntax'
import { getViewportLineRange, shouldDecorateEditorLine } from './viewport_lazy'

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

const DIAGRAM_MAX_HEIGHT_BLOCK = 320
const DIAGRAM_MAX_HEIGHT_INLINE = 128

function parseSvgLength(value) {
  if (!value) return null
  const n = parseFloat(String(value).trim())
  return Number.isFinite(n) && n > 0 ? n : null
}

function svgIntrinsicSize(svg) {
  const widthAttr = svg.getAttribute('width') ?? ''
  const heightAttr = svg.getAttribute('height') ?? ''
  let width = widthAttr && !widthAttr.includes('%') ? parseSvgLength(widthAttr) : null
  let height = heightAttr && !heightAttr.includes('%') ? parseSvgLength(heightAttr) : null

  if (width && height) return { width, height }

  const vb = svg.viewBox?.baseVal
  if (vb && vb.width > 0 && vb.height > 0) {
    return { width: vb.width, height: vb.height }
  }

  try {
    const box = svg.getBBox()
    if (box.width > 0 && box.height > 0) {
      return { width: box.width, height: box.height }
    }
  } catch {
    /* ignore */
  }

  return null
}

/** object 内 SVG の viewBox / width・height から表示サイズを決める（アスペクト比維持） */
function sizeDiagramObject(obj, { block }) {
  const apply = () => {
    try {
      const svg = obj.contentDocument?.documentElement
      if (!svg || svg.localName !== 'svg') return

      const intrinsic = svgIntrinsicSize(svg)
      if (!intrinsic) return

      const editor = obj.closest('.cm-editor')
      const maxWidth = Math.min(720, (editor?.clientWidth ?? 640) * 0.95)
      const maxHeight = block ? DIAGRAM_MAX_HEIGHT_BLOCK : DIAGRAM_MAX_HEIGHT_INLINE

      let { width, height } = intrinsic
      if (width > maxWidth) {
        height = (height * maxWidth) / width
        width = maxWidth
      }
      if (height > maxHeight) {
        width = (width * maxHeight) / height
        height = maxHeight
      }

      obj.style.width = `${Math.round(width)}px`
      obj.style.height = `${Math.round(height)}px`
    } catch {
      /* same-origin 想定。読めない場合は CSS の max-* に任せる */
    }
  }

  obj.addEventListener('load', apply)
  if (obj.contentDocument?.documentElement) apply()
}

function appendDiagramAction(actions, { href, label }) {
  if (!href) return
  const link = document.createElement('a')
  link.href = href
  link.target = '_blank'
  link.rel = 'noopener noreferrer'
  link.className = 'cm-wysiwyg-diagram-action'
  link.textContent = label
  actions.appendChild(link)
}

class DiagramPreviewWidget extends WidgetType {
  constructor({ src, label, editUrl, sourceUrl, viewUrl, block, from, to }) {
    super()
    this.src = src
    this.label = label
    this.editUrl = editUrl
    this.sourceUrl = sourceUrl
    this.viewUrl = viewUrl
    this.block = block
    this.from = from
    this.to = to
  }

  eq(other) {
    return (
      other.src === this.src &&
      other.label === this.label &&
      other.editUrl === this.editUrl &&
      other.sourceUrl === this.sourceUrl &&
      other.viewUrl === this.viewUrl &&
      other.block === this.block &&
      other.from === this.from &&
      other.to === this.to
    )
  }

  toDOM(view) {
    const fig = document.createElement('figure')
    fig.className = this.block
      ? 'cm-wysiwyg-diagram cm-wysiwyg-diagram--block cm-wysiwyg-diagram--clickable'
      : 'cm-wysiwyg-diagram cm-wysiwyg-diagram--inline cm-wysiwyg-diagram--clickable'

    fig.addEventListener('mousedown', (event) => {
      if (event.button !== 0) return
      if (event.target?.closest?.('.cm-wysiwyg-diagram-actions a')) return
      event.preventDefault()
      event.stopPropagation()
      activateDiagramMacro(view, this.from, this.to, this.block)
    })

    if (this.src) {
      const obj = document.createElement('object')
      obj.data = this.src
      obj.type = 'image/svg+xml'
      obj.className = 'cm-wysiwyg-diagram-object'
      obj.setAttribute('aria-label', this.label)
      sizeDiagramObject(obj, { block: this.block })
      fig.appendChild(obj)
    } else {
      const missing = document.createElement('span')
      missing.className = 'cm-wysiwyg-diagram-missing'
      missing.textContent = `diagram::${this.label}[]（SVG 未生成）`
      fig.appendChild(missing)
    }

    const actions = document.createElement('div')
    actions.className = 'cm-wysiwyg-diagram-actions'
    appendDiagramAction(actions, { href: this.editUrl, label: '編集' })
    appendDiagramAction(actions, { href: this.sourceUrl, label: 'ソース' })
    appendDiagramAction(actions, { href: this.viewUrl, label: 'ビューアで開く' })
    if (actions.childElementCount > 0) fig.appendChild(actions)

    return fig
  }

  ignoreEvent(event) {
    if (event.target?.closest?.('.cm-wysiwyg-diagram-actions a')) return true
    if (event.type === 'mousedown') return false
    return true
  }

  get estimatedHeight() {
    return this.block ? 120 : 64
  }
}

function activateDiagramMacro(view, from, to, block) {
  if (block) {
    const line = view.state.doc.lineAt(from)
    view.dispatch({
      selection: { anchor: line.from, head: line.to },
      scrollIntoView: true,
    })
  } else {
    view.dispatch({
      selection: { anchor: from, head: to },
      scrollIntoView: true,
    })
  }
  view.focus()
}

function buildDiagramDecorations(view, getMemoId) {
  const specs = []
  const atomicRanges = []
  const { state } = view
  const editingActive = view.hasFocus
  const memoId = getMemoId()
  const viewportRange = getViewportLineRange(state)

  const codeBlocks = scanCodeBlocks(state.doc)
  const codeByLine = codeBlockByLine(codeBlocks)
  const tableBlocks = scanTableBlocks(state.doc, (n) => codeByLine.has(n))
  const tableByLine = tableBlockByLine(tableBlocks)
  const skipLine = (n) => codeByLine.has(n) || tableByLine.has(n)

  for (let lineNo = 1; lineNo <= state.doc.lines; lineNo++) {
    if (skipLine(lineNo)) continue
    if (!shouldDecorateEditorLine(view, lineNo, viewportRange)) continue

    const line = state.doc.line(lineNo)
    const text = line.text
    const onLine = editingActive && cursorOnLine(state, line)

    const blockDiagram = parseBlockDiagramLine(text)
    if (blockDiagram && !onLine) {
      const macroPath = blockDiagram.macroPath
      const svgRel = diagramSvgRelativePath(macroPath)
      const src = svgRel ? memoAssetSrc(memoId, svgRel) : null
      pushSpec(
        specs,
        line.from,
        line.to,
        Decoration.replace({
          widget: new DiagramPreviewWidget({
            src,
            label: macroPath,
            editUrl: diagramEditUrl(memoId, macroPath),
            sourceUrl: diagramSourceUrl(memoId, macroPath),
            viewUrl: src ? diagramViewUrl(memoId, macroPath) : null,
            block: true,
            from: line.from,
            to: line.to,
          }),
        }),
      )
      atomicRanges.push({ from: line.from, to: line.to })
      continue
    }

    if (onLine) continue

    for (const macro of scanDiagramMacrosOnLine(text, line.from)) {
      if (blockDiagram && macro.from === line.from && macro.to === line.to) continue
      if (editingActive && selectionTouches(state, macro.from, macro.to)) continue

      const macroPath = macro.macroPath
      const svgRel = diagramSvgRelativePath(macroPath)
      const src = svgRel ? memoAssetSrc(memoId, svgRel) : null
      pushSpec(
        specs,
        macro.from,
        macro.to,
        Decoration.replace({
          widget: new DiagramPreviewWidget({
            src,
            label: macroPath,
            editUrl: diagramEditUrl(memoId, macroPath),
            sourceUrl: diagramSourceUrl(memoId, macroPath),
            viewUrl: src ? diagramViewUrl(memoId, macroPath) : null,
            block: false,
            from: macro.from,
            to: macro.to,
          }),
        }),
      )
      atomicRanges.push({ from: macro.from, to: macro.to })
    }
  }

  const decorations = Decoration.set(
    specs.map((spec) => spec.deco.range(spec.from, spec.to)),
    true,
  )

  const atomic =
    atomicRanges.length > 0
      ? RangeSet.of(
          atomicRanges.map((r) => Decoration.replace({}).range(r.from, r.to)),
          true,
        )
      : RangeSet.empty

  return { decorations, atomicRanges: atomic }
}

/**
 * WYSIWYG ソース CM: `diagram::` → キャッシュ済み SVG（object）プレビュー。
 */
export function diagramWysiwygExtension(getMemoId) {
  const plugin = ViewPlugin.fromClass(
    class {
      constructor(view) {
        const built = buildDiagramDecorations(view, getMemoId)
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
          const built = buildDiagramDecorations(update.view, getMemoId)
          this.decorations = built.decorations
          this.atomicRanges = built.atomicRanges
        }
      }
    },
    {
      decorations: (v) => v.decorations,
      provide: (plugin) =>
        EditorView.atomicRanges.of((view) => view.plugin(plugin)?.atomicRanges ?? RangeSet.empty),
    },
  )

  return plugin
}
