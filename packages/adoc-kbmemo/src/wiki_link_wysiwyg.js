import { RangeSet, RangeSetBuilder, StateEffect, StateField } from "@codemirror/state"
import { Decoration, EditorView, ViewPlugin } from "@codemirror/view"
import { getViewportLineRange, shouldDecorateEditorLine } from "./viewport_lazy"
import { KbmemoWidgetType } from "./widget_type_compat"
import { wikiMemoLinkPath } from "../hostConfig.js"

const WIKI_LINK = /\[\[([^\]|]+?)(?:\|([^\]]+?))?\]\]/g
const LINK_LABEL = /((?:[^\\\]]|\\.)*)/
const MEMO_LINK_TOKEN = String.raw`(?:\d+|[0-9A-HJKMNP-TV-Z]{26})`
const ASCIIDOC_MEMO_LINK = new RegExp(
  String.raw`link:(?:/memos/(${MEMO_LINK_TOKEN})|memos/(${MEMO_LINK_TOKEN}))\[` + LINK_LABEL.source + String.raw`\]`,
  "gi"
)
const ASCIIDOC_URL_LINK =
  /((?:https?:\/\/|ftp:\/\/|file:\/\/|mailto:|callto:)[^\s\[]+)\[((?:[^\\\]]|\\.)*)\]/gi
const ASCIIDOC_LINK = /link:([^\s\[]+)\[((?:[^\\\]]|\\.)*)\]/gi
const ASCIIDOC_XREF = /<<([^>,\]]+?)(?:,((?:[^\\\]]|\\.)*))?>>/g
const FENCE_LINE = /^```/

const LINK_SCANNERS = [
  WIKI_LINK,
  ASCIIDOC_MEMO_LINK,
  ASCIIDOC_URL_LINK,
  ASCIIDOC_LINK,
  ASCIIDOC_XREF
]

const KIND_ORDER = { line: 0, replace: 1, mark: 2 }

const setWikiLabelsEffect = StateEffect.define()

const wikiLabelsField = StateField.define({
  create() {
    return { labels: new Map(), generation: 0 }
  },
  update(value, tr) {
    let labels = value.labels
    let generation = value.generation
    for (const effect of tr.effects) {
      if (effect.is(setWikiLabelsEffect)) {
        labels = new Map(labels)
        for (const [key, entry] of effect.value) {
          labels.set(key, entry)
        }
        generation += 1
      }
    }
    return { labels, generation }
  }
})

function selectionTouches(state, from, to) {
  return state.selection.ranges.some((range) => {
    const start = Math.min(range.anchor, range.head)
    const end = Math.max(range.anchor, range.head)
    return start < to && end > from
  })
}

function pushSpec(specs, from, to, deco, kind) {
  specs.push({ from, to, deco, kind })
}

function sortSpecs(specs) {
  specs.sort((a, b) => {
    if (a.from !== b.from) return a.from - b.from
    if (a.to !== b.to) return a.to - b.to
    return KIND_ORDER[a.kind] - KIND_ORDER[b.kind]
  })
}

function unescapeLinkLabel(text) {
  return text.replace(/\\\]/g, "]")
}

function memoHref(memoRef) {
  return wikiMemoLinkPath(memoRef)
}

function isUrlHref(href) {
  return /^(https?:|ftp:|mailto:|callto:|file:)/i.test(href)
}

function memoLinkRefFromHref(href) {
  const m = href.match(new RegExp(`^\\/?memos\\/(${MEMO_LINK_TOKEN})$`, "i"))
  return m ? m[1] : null
}

/** wysiwyg_lite のインライン装飾から除外するリンク範囲 */
export function linkExclusionRanges(text, lineFrom) {
  const ranges = []
  for (const re of LINK_SCANNERS) {
    const flags = re.flags.includes("g") ? re.flags : `${re.flags}g`
    const scanner = new RegExp(re.source, flags)
    for (const match of text.matchAll(scanner)) {
      ranges.push([lineFrom + match.index, lineFrom + match.index + match[0].length])
    }
  }
  return ranges
}

class LinkLabelWidget extends KbmemoWidgetType {
  constructor(label, { broken = false, memoRef = null, href = null, external = false } = {}) {
    super()
    this.label = label
    this.broken = broken
    this.memoRef = memoRef
    this.href = href
    this.external = external
  }

  eq(other) {
    return (
      other.label === this.label &&
      other.broken === this.broken &&
      other.memoRef === this.memoRef &&
      other.href === this.href &&
      other.external === this.external
    )
  }

  toDOM() {
    const navigable = !this.broken && (this.memoRef != null || this.href)
    if (navigable) {
      const a = document.createElement("a")
      a.href = this.memoRef != null ? memoHref(this.memoRef) : this.href
      a.className = "cm-memo-wiki-link cm-memo-wiki-link--open"
      if (this.external) {
        a.target = "_blank"
        a.rel = "noopener noreferrer"
      }
      a.textContent = this.label
      return a
    }

    const span = document.createElement("span")
    span.className = this.broken
      ? "cm-memo-wiki-link cm-memo-wiki-link--broken"
      : "cm-memo-wiki-link"
    span.textContent = this.label
    return span
  }

  ignoreEvent(event) {
    if (this.broken || (this.memoRef == null && !this.href)) return false
    return event.type === "mousedown" || event.type === "click"
  }
}

function linkWidget(label, entry, { href = null, external = false, memoRef = null } = {}) {
  if (memoRef != null) {
    return new LinkLabelWidget(label, { memoRef, broken: false })
  }
  if (href) {
    return new LinkLabelWidget(label, { href, external, broken: false })
  }
  if (!entry) {
    return new LinkLabelWidget(label, { broken: false })
  }
  return new LinkLabelWidget(label, {
    broken: !entry.resolved,
    memoRef: entry.resolved ? (entry.memo_uid ?? entry.memo_id ?? null) : null
  })
}

function applyLinkPreview(specs, atomicRanges, hiddenBefore, innerFrom, innerTo, hiddenAfter, widget) {
  for (const [from, to] of hiddenBefore) {
    pushSpec(specs, from, to, Decoration.replace({}), "replace")
    atomicRanges.push({ from, to })
  }
  pushSpec(specs, innerFrom, innerTo, Decoration.replace({ widget }), "replace")
  atomicRanges.push({ from: innerFrom, to: innerTo })
  for (const [from, to] of hiddenAfter) {
    pushSpec(specs, from, to, Decoration.replace({}), "replace")
    atomicRanges.push({ from, to })
  }
}

function collectResolveTargets(doc) {
  const targets = new Set()
  let inFenced = false

  for (let lineNo = 1; lineNo <= doc.lines; lineNo++) {
    const text = doc.line(lineNo).text
    if (FENCE_LINE.test(text)) {
      inFenced = !inFenced
      continue
    }
    if (inFenced) continue

    for (const match of text.matchAll(WIKI_LINK)) {
      const target = match[1].trim()
      if (target) targets.add(target)
    }

    for (const match of text.matchAll(ASCIIDOC_LINK)) {
      const href = match[1].trim()
      if (!href || isUrlHref(href) || memoLinkRefFromHref(href)) continue
      targets.add(href)
    }

    for (const match of text.matchAll(ASCIIDOC_XREF)) {
      const target = match[1].trim()
      if (target) targets.add(target)
    }
  }

  return targets
}

let fetchSeq = 0

async function fetchWikiLabels(url, memoId, targets) {
  if (!url || targets.length === 0) return []

  const endpoint = new URL(url, window.location.origin)
  if (memoId) endpoint.searchParams.set("memo_id", memoId)
  for (const target of targets) {
    endpoint.searchParams.append("targets[]", target)
  }

  const res = await fetch(endpoint.toString(), {
    headers: { Accept: "application/json" },
    credentials: "same-origin"
  })
  if (!res.ok) return []

  const data = await res.json()
  return Object.entries(data)
}

function decorateWikiLink(specs, atomicRanges, match, lineFrom, labels) {
  const fullFrom = lineFrom + match.index
  const fullTo = fullFrom + match[0].length
  const target = match[1].trim()
  const custom = match[2]?.trim()
  const entry = labels.get(target)

  if (custom) {
    if (!entry) return false
    applyLinkPreview(
      specs,
      atomicRanges,
      [[fullFrom, fullFrom + 2]],
      fullFrom + 2,
      fullTo - 2,
      [[fullTo - 2, fullTo]],
      linkWidget(unescapeLinkLabel(custom), entry)
    )
    return true
  }

  if (!entry) return false

  const display =
    entry.slug && entry.resolved ? entry.display : entry.display ?? target
  applyLinkPreview(
    specs,
    atomicRanges,
    [[fullFrom, fullFrom + 2]],
    fullFrom + 2,
    fullTo - 2,
    [[fullTo - 2, fullTo]],
    linkWidget(display, entry)
  )
  return true
}

function decorateAsciiDocMemoLink(specs, atomicRanges, match, lineFrom) {
  const fullFrom = lineFrom + match.index
  const fullTo = fullFrom + match[0].length
  const memoRef = match[1] || match[2]
  const label = unescapeLinkLabel(match[3])
  const bracketOpen = match[0].indexOf("[")
  const innerFrom = fullFrom + bracketOpen + 1
  const innerTo = fullTo - 1

  applyLinkPreview(
    specs,
    atomicRanges,
    [[fullFrom, innerFrom]],
    innerFrom,
    innerTo,
    [[innerTo, fullTo]],
    linkWidget(label, null, { memoRef })
  )
  return true
}

function decorateAsciiDocUrlLink(specs, atomicRanges, match, lineFrom) {
  const fullFrom = lineFrom + match.index
  const fullTo = fullFrom + match[0].length
  const href = match[1]
  const label = unescapeLinkLabel(match[2])
  const bracketOpen = match[0].indexOf("[")
  const innerFrom = fullFrom + bracketOpen + 1
  const innerTo = fullTo - 1

  applyLinkPreview(
    specs,
    atomicRanges,
    [[fullFrom, innerFrom]],
    innerFrom,
    innerTo,
    [[innerTo, fullTo]],
    linkWidget(label || href, null, { href, external: true })
  )
  return true
}

function decorateAsciiDocLink(specs, atomicRanges, match, lineFrom, labels) {
  const href = match[1].trim()
  if (isUrlHref(href) || memoLinkRefFromHref(href)) return false

  const fullFrom = lineFrom + match.index
  const fullTo = fullFrom + match[0].length
  const label = unescapeLinkLabel(match[2])
  const entry = labels.get(href)
  if (!entry) return false

  const bracketOpen = match[0].indexOf("[")
  const innerFrom = fullFrom + bracketOpen + 1
  const innerTo = fullTo - 1
  const display =
    entry.slug && entry.resolved && !label ? entry.display : label || entry.display || href

  applyLinkPreview(
    specs,
    atomicRanges,
    [[fullFrom, innerFrom]],
    innerFrom,
    innerTo,
    [[innerTo, fullTo]],
    linkWidget(display, entry)
  )
  return true
}

function decorateAsciiDocXref(specs, atomicRanges, match, lineFrom, labels) {
  const fullFrom = lineFrom + match.index
  const fullTo = fullFrom + match[0].length
  const target = match[1].trim()
  const custom = match[2]
  const entry = labels.get(target)

  if (custom != null) {
    if (!entry) return false
    const commaAt = fullFrom + 2 + target.length
    applyLinkPreview(
      specs,
      atomicRanges,
      [
        [fullFrom, fullFrom + 2],
        [commaAt, commaAt + 1]
      ],
      commaAt + 1,
      fullTo - 2,
      [[fullTo - 2, fullTo]],
      linkWidget(unescapeLinkLabel(custom), entry)
    )
    return true
  }

  if (!entry) return false

  const display = entry.slug && entry.resolved ? entry.display : entry.display ?? target
  applyLinkPreview(
    specs,
    atomicRanges,
    [[fullFrom, fullFrom + 2]],
    fullFrom + 2,
    fullTo - 2,
    [[fullTo - 2, fullTo]],
    linkWidget(display, entry)
  )
  return true
}

function buildLinkDecorations(view, labels) {
  const specs = []
  const atomicRanges = []
  const { state } = view
  const editingActive = view.hasFocus
  let inFenced = false
  const viewportRange = getViewportLineRange(state)

  for (let lineNo = 1; lineNo <= state.doc.lines; lineNo++) {
    const line = state.doc.line(lineNo)
    const text = line.text

    if (!shouldDecorateEditorLine(view, lineNo, viewportRange)) continue

    if (FENCE_LINE.test(text)) {
      inFenced = !inFenced
      continue
    }
    if (inFenced) continue

    const occupied = []

    const overlaps = (from, to) => occupied.some((span) => from < span.to && to > span.from)

    const markRange = (from, to) => {
      occupied.push({ from, to })
    }

    const tryDecorate = (from, to, decorate) => {
      if (overlaps(from, to)) return
      if (editingActive && selectionTouches(state, from, to)) return
      if (decorate()) markRange(from, to)
    }

    for (const match of text.matchAll(WIKI_LINK)) {
      const from = line.from + match.index
      const to = from + match[0].length
      tryDecorate(from, to, () => decorateWikiLink(specs, atomicRanges, match, line.from, labels))
    }

    for (const match of text.matchAll(ASCIIDOC_MEMO_LINK)) {
      const from = line.from + match.index
      const to = from + match[0].length
      tryDecorate(from, to, () => decorateAsciiDocMemoLink(specs, atomicRanges, match, line.from))
    }

    for (const match of text.matchAll(ASCIIDOC_URL_LINK)) {
      const from = line.from + match.index
      const to = from + match[0].length
      tryDecorate(from, to, () => decorateAsciiDocUrlLink(specs, atomicRanges, match, line.from))
    }

    for (const match of text.matchAll(ASCIIDOC_LINK)) {
      const from = line.from + match.index
      const to = from + match[0].length
      tryDecorate(from, to, () =>
        decorateAsciiDocLink(specs, atomicRanges, match, line.from, labels)
      )
    }

    for (const match of text.matchAll(ASCIIDOC_XREF)) {
      const from = line.from + match.index
      const to = from + match[0].length
      tryDecorate(from, to, () => decorateAsciiDocXref(specs, atomicRanges, match, line.from, labels))
    }
  }

  sortSpecs(specs)

  const builder = new RangeSetBuilder()
  for (const spec of specs) {
    builder.add(spec.from, spec.to, spec.deco)
  }

  atomicRanges.sort((a, b) => a.from - b.from || a.to - b.to)

  const atomic =
    atomicRanges.length > 0
      ? RangeSet.of(atomicRanges.map((r) => Decoration.replace({}).range(r.from, r.to)))
      : RangeSet.empty

  return { decorations: builder.finish(), atomicRanges: atomic }
}

/**
 * [[wiki]] / AsciiDoc link / xref の WYSIWYG。スラッグ解決時はタイトル表示、解決済みはクリックで開く。
 */
export function wikiLinkWysiwygExtension(getConfig) {
  const plugin = ViewPlugin.fromClass(
    class {
      constructor(view) {
        this.labelsGeneration = -1
        this.decorations = Decoration.none
        this.atomicRanges = RangeSet.empty
        this.labelsGeneration = view.state.field(wikiLabelsField).generation
        this.rebuild(view)
        this.scheduleFetch(view)
      }

      rebuild(view) {
        const { labels } = view.state.field(wikiLabelsField)
        const built = buildLinkDecorations(view, labels)
        this.decorations = built.decorations
        this.atomicRanges = built.atomicRanges
      }

      scheduleFetch(view) {
        const { url, memoId } = getConfig()
        const { labels } = view.state.field(wikiLabelsField)
        const missing = [...collectResolveTargets(view.state.doc)].filter((t) => !labels.has(t))
        if (missing.length === 0) return

        const seq = ++fetchSeq
        fetchWikiLabels(url, memoId, missing).then((entries) => {
          if (seq !== fetchSeq || entries.length === 0) return
          view.dispatch({
            effects: setWikiLabelsEffect.of(entries)
          })
        })
      }

      update(update) {
        const labelGen = update.state.field(wikiLabelsField).generation
        const needsRebuild =
          update.docChanged ||
          update.selectionSet ||
          update.viewportChanged ||
          update.focusChanged ||
          labelGen !== this.labelsGeneration

        if (needsRebuild) {
          this.labelsGeneration = labelGen
          this.rebuild(update.view)
        }

        if (update.docChanged) {
          this.scheduleFetch(update.view)
        }
      }
    },
    {
      decorations: (v) => v.decorations,
      provide: (plugin) =>
        EditorView.atomicRanges.of((view) => view.plugin(plugin)?.atomicRanges ?? RangeSet.empty)
    }
  )

  return [wikiLabelsField, plugin]
}
