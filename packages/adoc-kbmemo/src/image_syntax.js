/** AsciiDoc 画像マクロ（`image::` / `image:`）のパス正規化 */

const IMAGE_MACRO_RE = /image::([^\[\]\s]+)(\[[^\]]*\])?|image:([^\[\]\s]+)(\[[^\]]*\])/g

const MEMO_ASSET_URL_RE = /^\/memos\/(\d+)\/assets\/(.+)$/i
const MEMO_ASSET_REL_URL_RE = /^memos\/(\d+)\/assets\/(.+)$/i

function decodePathSegments(path) {
  return path
    .split("/")
    .map((seg) => {
      try {
        return decodeURIComponent(seg)
      } catch {
        return seg
      }
    })
    .join("/")
}

/** `/memos/:id/assets/...` をアセット相対パスへ（imagesdir 二重付与の防止） */
export function memoAssetRelativePath(memoId, src) {
  if (!src?.trim()) return src ?? ""

  const original = src.trim()
  let path = original
  if (path.includes("://")) {
    try {
      path = new URL(path).pathname
    } catch {
      return original
    }
  }

  path = path.replace(/\\/g, "/").replace(/^\/+/, (m) => (m ? "/" : ""))

  let changed = true
  while (changed) {
    changed = false
    const abs = path.match(MEMO_ASSET_URL_RE)
    if (abs) {
      if (memoId != null && String(abs[1]) !== String(memoId)) return original
      path = decodePathSegments(abs[2])
      changed = true
      continue
    }

    const rel = path.match(MEMO_ASSET_REL_URL_RE)
    if (rel) {
      if (memoId != null && String(rel[1]) !== String(memoId)) return original
      path = decodePathSegments(rel[2])
      changed = true
    }
  }

  return path.replace(/^\.\//, "")
}

/** 本文中の image マクロパスをアセット相対パスへ正規化 */
export function normalizeMemoImagePathsInSource(source, memoId) {
  if (!source || memoId == null || memoId === "") return source

  return source.replace(IMAGE_MACRO_RE, (full, blockPath, blockTail, inlinePath, inlineTail) => {
    const raw = (blockPath || inlinePath || "").trim()
    const rel = memoAssetRelativePath(memoId, raw)
    if (full.startsWith("image::")) {
      return `image::${rel}${blockTail ?? ""}`
    }
    return `image:${rel}${inlineTail ?? ""}`
  })
}

/** メモアセット URL（表示・memo_html の imagesdir と同じ規則） */
export function memoAssetSrc(memoId, filename) {
  if (!memoId || !filename?.trim()) return null
  const relative = memoAssetRelativePath(memoId, filename.trim())
  if (!relative) return null
  const path = relative
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
