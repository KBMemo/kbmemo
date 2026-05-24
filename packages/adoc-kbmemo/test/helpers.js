/** @param {string} text */
export function mockDoc(text) {
  const lines = text.split('\n')
  return {
    lines: lines.length,
    line(lineNo) {
      return { text: lines[lineNo - 1] ?? '' }
    },
  }
}
