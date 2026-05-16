import { RangeSet, RangeSetBuilder, StateEffect, StateField } from "@codemirror/state"
import { Decoration, EditorView, ViewPlugin, WidgetType } from "@codemirror/view"

const WIKI_LINK = /\[\[([^\]|]+?)(?:\|([^\]]+?))?\]\]/g
const FENCE_LINE = /^```/

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

function memoHref(memoId) {
  return `/memos/${memoId}`
}

class WikiLinkLabelWidget extends WidgetType {
  constructor(label, { broken = false, memoId = null } = {}) {
    super()
    this.label = label
    this.broken = broken
    this.memoId = memoId
  }

  eq(other) {
    return (
      other.label === this.label &&
      other.broken === this.broken &&
      other.memoId === this.memoId
    )
  }

  toDOM() {
    if (this.memoId && !this.broken) {
      const a = document.createElement("a")
      a.href = memoHref(this.memoId)
      a.className = "cm-memo-wiki-link cm-memo-wiki-link--open"
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
    if (!this.memoId || this.broken) return false
    return event.type === "mousedown" || event.type === "click"
  }
}

function wikiLinkWidget(label, entry) {
  if (!entry) {
    return new WikiLinkLabelWidget(label, { broken: false })
  }
  return new WikiLinkLabelWidget(label, {
    broken: !entry.resolved,
    memoId: entry.resolved ? entry.memo_id : null
  })
}

function collectWikiTargets(doc) {
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

function hideBrackets(specs, atomicRanges, fullFrom, fullTo) {
  pushSpec(specs, fullFrom, fullFrom + 2, Decoration.replace({}), "replace")
  pushSpec(specs, fullTo - 2, fullTo, Decoration.replace({}), "replace")
  atomicRanges.push({ from: fullFrom, to: fullFrom + 2 }, { from: fullTo - 2, to: fullTo })
}

function applyWikiLinkWysiwyg(specs, atomicRanges, fullFrom, fullTo, innerFrom, innerTo, widget) {
  hideBrackets(specs, atomicRanges, fullFrom, fullTo)
  pushSpec(specs, innerFrom, innerTo, Decoration.replace({ widget }), "replace")
  atomicRanges.push({ from: innerFrom, to: innerTo })
}

function buildWikiLinkDecorations(view, labels) {
  const specs = []
  const atomicRanges = []
  const { state } = view
  const editingActive = view.hasFocus
  let inFenced = false

  for (let lineNo = 1; lineNo <= state.doc.lines; lineNo++) {
    const line = state.doc.line(lineNo)
    const text = line.text

    if (FENCE_LINE.test(text)) {
      inFenced = !inFenced
      continue
    }
    if (inFenced) continue

    for (const match of text.matchAll(WIKI_LINK)) {
      const fullFrom = line.from + match.index
      const fullTo = fullFrom + match[0].length
      if (editingActive && selectionTouches(state, fullFrom, fullTo)) continue

      const target = match[1].trim()
      const custom = match[2]?.trim()
      const innerFrom = fullFrom + 2
      const innerTo = fullTo - 2
      const entry = labels.get(target)

      if (custom) {
        if (!entry) continue
        applyWikiLinkWysiwyg(
          specs,
          atomicRanges,
          fullFrom,
          fullTo,
          innerFrom,
          innerTo,
          wikiLinkWidget(custom, entry)
        )
        continue
      }

      if (!entry) continue

      const display =
        entry.slug && entry.resolved ? entry.display : entry.display ?? target
      applyWikiLinkWysiwyg(
        specs,
        atomicRanges,
        fullFrom,
        fullTo,
        innerFrom,
        innerTo,
        wikiLinkWidget(display, entry)
      )
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
 * [[slug]] を WYSIWYG 時にタイトル表示。解決済みはクリックでメモを開く。
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
        const built = buildWikiLinkDecorations(view, labels)
        this.decorations = built.decorations
        this.atomicRanges = built.atomicRanges
      }

      scheduleFetch(view) {
        const { url, memoId } = getConfig()
        const { labels } = view.state.field(wikiLabelsField)
        const missing = [...collectWikiTargets(view.state.doc)].filter((t) => !labels.has(t))
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
