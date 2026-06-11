let highlighterPromise = null

function loadHighlighter() {
  highlighterPromise ??= import('../../packages/adoc-codemirror/src/codeHighlight.js')
  return highlighterPromise
}

/** @param {ParentNode} [root] */
export function highlightMemoBodies(root = document) {
  const containers = root.querySelectorAll('.memo-body.asciidoctor')
  if (containers.length === 0) return

  loadHighlighter().then(({ highlightPreviewCode }) => {
    containers.forEach((container) => {
      highlightPreviewCode(container)
    })
  }).catch((error) => {
    console.error("Failed to load memo body highlighter", error)
  })
}
