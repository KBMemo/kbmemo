import { highlightPreviewCode } from '@kbmemo/adoc-codemirror'

/** @param {ParentNode} [root] */
export function highlightMemoBodies(root = document) {
  root.querySelectorAll('.memo-body.asciidoctor').forEach((container) => {
    highlightPreviewCode(container)
  })
}
