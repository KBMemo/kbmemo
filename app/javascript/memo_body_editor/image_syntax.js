/** AsciiDoc 画像マクロ（`image::` / `image:`）の解析 */

const BLOCK_IMAGE_LINE = /^(\s*)image::([^\[\]]+?)(\[[^\]]*\])?\s*$/

const IMAGE_MACRO_RE = /image::([^\[\]\s]+)(\[[^\]]*\])?|image:([^\[\]\s]+)(\[[^\]]*\])/g

/** メモアセット URL（表示・memo_html の imagesdir と同じ規則） */
export function memoAssetSrc(memoId, filename) {
  if (!memoId || !filename?.trim()) return null
  const path = filename
    .trim()
    .split("/")
    .map((seg) => encodeURIComponent(seg))
    .join("/")
  return `/memos/${encodeURIComponent(String(memoId))}/assets/${path}`
}

/** 拡大縮小ビューア（/assets/.../view） */
export function memoAssetViewUrl(memoId, filename) {
  const src = memoAssetSrc(memoId, filename)
  return src ? `${src}/view` : null
}

/** 行全体がブロック画像マクロのみのとき */
export function parseBlockImageLine(text) {
  const match = text.match(BLOCK_IMAGE_LINE)
  if (!match) return null
  return { filename: match[2].trim(), indentLength: match[1].length }
}

/** 行内の画像マクロ（ブロック行は呼び出し側で別処理） */
export function scanImageMacrosOnLine(text, lineFrom) {
  const results = []
  const re = new RegExp(IMAGE_MACRO_RE.source, "g")
  for (const match of text.matchAll(re)) {
    const full = match[0]
    const block = full.startsWith("image::")
    const filename = (block ? match[1] : match[3]).trim()
    results.push({
      from: lineFrom + match.index,
      to: lineFrom + match.index + full.length,
      filename,
      block
    })
  }
  return results
}

/** wysiwyg_lite のインライン装飾から除外する画像マクロ範囲 */
export function imageExclusionRanges(text, lineFrom) {
  return scanImageMacrosOnLine(text, lineFrom).map((m) => [m.from, m.to])
}
