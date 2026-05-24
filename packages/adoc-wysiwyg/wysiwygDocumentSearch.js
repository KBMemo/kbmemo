/** @typedef {{ from: number, to: number }} DocumentMatch */

/** @typedef {{ unit: HTMLElement, text: string, from: number, to: number }} DocumentSegment */

/**
 * @param {string} source
 * @param {string} query
 * @param {boolean} caseSensitive
 * @returns {DocumentMatch[]}
 */
export function findDocumentMatches(source, query, caseSensitive) {
  if (!query) return []

  const haystack = caseSensitive ? source : source.toLowerCase()
  const needle = caseSensitive ? query : query.toLowerCase()
  /** @type {DocumentMatch[]} */
  const matches = []

  let index = 0
  while (index <= haystack.length) {
    const found = haystack.indexOf(needle, index)
    if (found === -1) break
    matches.push({ from: found, to: found + needle.length })
    index = found + needle.length
  }

  return matches
}

/**
 * @param {DocumentMatch[]} matches
 * @param {number} cursor
 * @param {boolean} reverse
 */
export function pickNextDocumentMatch(matches, cursor, reverse = false) {
  if (matches.length === 0) return -1

  if (reverse) {
    for (let index = matches.length - 1; index >= 0; index--) {
      if (matches[index].from < cursor) return index
    }
    return matches.length - 1
  }

  for (let index = 0; index < matches.length; index++) {
    if (matches[index].from > cursor) return index
  }
  return 0
}

/**
 * @param {string} source
 * @param {DocumentMatch} match
 * @param {string} replacement
 */
export function replaceDocumentMatch(source, match, replacement) {
  return source.slice(0, match.from) + replacement + source.slice(match.to)
}

/**
 * @param {string} source
 * @param {string} query
 * @param {string} replacement
 * @param {boolean} caseSensitive
 */
export function replaceAllInDocument(source, query, replacement, caseSensitive) {
  if (!query) return { source, count: 0 }

  const matches = findDocumentMatches(source, query, caseSensitive)
  if (matches.length === 0) return { source, count: 0 }

  let nextSource = source
  for (let index = matches.length - 1; index >= 0; index--) {
    nextSource = replaceDocumentMatch(nextSource, matches[index], replacement)
  }

  return { source: nextSource, count: matches.length }
}

/**
 * @param {string} source
 */
export function normalizeDocumentSource(source) {
  const trimmed = source.trimEnd()
  return trimmed + (trimmed ? '\n' : '')
}

/**
 * @param {string} source
 * @returns {{ text: string, from: number, to: number }[]}
 */
export function buildSourceSegments(source) {
  const normalized = source.trimEnd()
  if (!normalized) return []

  /** @type {{ text: string, from: number, to: number }[]} */
  const segments = []
  let offset = 0

  for (const raw of normalized.split('\n\n')) {
    const text = raw.trim()
    if (!text) continue

    const from = offset
    const to = offset + text.length
    segments.push({ text, from, to })
    offset = to + 2
  }

  return segments
}

/**
 * @param {{ from: number, to: number }[]} segments
 * @param {number} offset
 */
export function findSegmentIndexForOffset(segments, offset) {
  for (let index = 0; index < segments.length; index++) {
    if (offset >= segments[index].from && offset <= segments[index].to) {
      return index
    }
  }

  for (let index = 0; index < segments.length - 1; index++) {
    const gapStart = segments[index].to
    const gapEnd = segments[index + 1].from
    if (offset > gapStart && offset < gapEnd) {
      return index
    }
  }

  return Math.max(0, segments.length - 1)
}

/**
 * @param {string} restored
 * @param {string} other
 * @param {number} [fallback]
 */
export function findChangeCursorPosition(restored, other, fallback = 0) {
  const left = restored.trimEnd()
  const right = other.trimEnd()
  if (left === right) return fallback

  let start = 0
  const minLength = Math.min(left.length, right.length)
  while (start < minLength && left[start] === right[start]) {
    start++
  }

  let endRestored = left.length
  let endOther = right.length
  while (
    endRestored > start &&
    endOther > start &&
    left[endRestored - 1] === right[endOther - 1]
  ) {
    endRestored--
    endOther--
  }

  if (endOther > endRestored) {
    return start
  }
  if (endRestored > endOther) {
    return endRestored
  }
  return start
}

/**
 * @param {DocumentSegment[]} segments
 * @param {number} offset
 */
export function findSegmentForOffset(segments, offset) {
  for (const segment of segments) {
    if (offset >= segment.from && offset <= segment.to) {
      return segment
    }
  }

  for (let index = 0; index < segments.length - 1; index++) {
    const gapStart = segments[index].to
    const gapEnd = segments[index + 1].from
    if (offset > gapStart && offset < gapEnd) {
      return segments[index]
    }
  }

  return segments[segments.length - 1] ?? null
}
