const BLOCK_PASSTHROUGH_DELIM = '++++'

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
 * @param {string} source
 */
function restrictInlinePassthrough(source) {
  let result = source.replace(/(?<!\\)pass:\[/g, '\\pass:[')
  result = result.replace(/(?<!\\)\+\+\+([^+\n]*)(?<!\\)\+\+\+/g, '\\+++$1+++')
  return result
}
