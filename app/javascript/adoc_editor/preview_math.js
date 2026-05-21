import renderMathInElement from 'katex/contrib/auto-render'

const PREVIEW_MATH_DELIMITERS = [
  { left: String.raw`\(`, right: String.raw`\)`, display: false },
  { left: String.raw`\[`, right: String.raw`\]`, display: true },
]

/**
 * Asciidoctor.js（:stem: latexmath）が出力する \( \) / \[ \] を KaTeX で描画する。
 *
 * @param {ParentNode} container
 */
export function renderPreviewMath(container) {
  renderMathInElement(container, {
    delimiters: PREVIEW_MATH_DELIMITERS,
    throwOnError: false,
    strict: 'ignore',
  })
}
