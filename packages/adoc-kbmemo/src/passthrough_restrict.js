const BLOCK_PASSTHROUGH_DELIM = '++++'

// [stem] / [latexmath] / [asciimath] ブロックの ++++ は passthrough（生 HTML）ではなく
// 数式ブロック（KaTeX 変換対象）なので neutralize しない。
const STEM_BLOCK_ATTR = /^\[(?:stem|latexmath|asciimath)\b/

/**
 * Neutralize AsciiDoc passthrough markup before HTML conversion.
 * Stored source is unchanged; call only on preview/show pipelines.
 *
 * @param {string} source
 * @returns {string}
 */
export function restrictPassthroughInSource(source) {
  if (!source) return source
  return restrictInlinePassthrough(restrictBlockPassthrough(source))
}

/**
 * @param {string} source
 */
function restrictBlockPassthrough(source) {
  const lines = source.split('\n')
  let index = 0

  while (index < lines.length) {
    if (lines[index]?.trim() !== BLOCK_PASSTHROUGH_DELIM) {
      index++
      continue
    }

    const openLine = index
    let closeLine = openLine
    let scan = openLine + 1

    while (scan < lines.length) {
      if (lines[scan]?.trim() === BLOCK_PASSTHROUGH_DELIM) {
        closeLine = scan
        break
      }
      scan++
    }

    if (isStemBlock(lines, openLine)) {
      index = closeLine === openLine ? openLine + 1 : closeLine + 1
      continue
    }

    lines[openLine] = lines[openLine].replace(BLOCK_PASSTHROUGH_DELIM, '....')

    if (closeLine === openLine) {
      lines.push('....')
      index = lines.length
      continue
    }

    lines[closeLine] = lines[closeLine].replace(BLOCK_PASSTHROUGH_DELIM, '....')
    index = closeLine + 1
  }

  return lines.join('\n')
}

/**
 * 開始 ++++ の直上にある連続メタ行に stem/latexmath/asciimath 属性があれば数式ブロック。
 * @param {string[]} lines
 * @param {number} openLine
 */
function isStemBlock(lines, openLine) {
  for (let i = openLine - 1; i >= 0; i--) {
    const line = lines[i]?.trim() ?? ''
    if (line === '') break
    if (STEM_BLOCK_ATTR.test(line)) return true
    if (!line.startsWith('[') && !line.startsWith('.')) break
  }
  return false
}

/**
 * @param {string} source
 */
function restrictInlinePassthrough(source) {
  let result = source.replace(/(?<!\\)pass:\[/g, '\\pass:[')
  result = result.replace(/(?<!\\)\+\+\+([^+\n]*)(?<!\\)\+\+\+/g, '\\+++$1+++')
  return result
}
