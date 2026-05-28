/** AsciiDoc 画像マクロ（`image::` / `image:`）のパス正規化 */

import { memoAssetSrc as buildMemoAssetSrc, memoAssetViewUrl as buildMemoAssetViewUrl } from '../hostConfig.js'

const IMAGE_MACRO_RE = /image::([^\[\]\s]+)(\[[^\]]*\])?|image:([^\[\]\s]+)(\[[^\]]*\])/g

const MEMO_ASSET_URL_RE = /^\/memos\/(\d+)\/assets\/(.+)$/i
const MEMO_ASSET_REL_URL_RE = /^memos\/(\d+)\/assets\/(.+)$/i
const KNOWN_URI_SCHEME_RE = /^(https?|data|file|ftp|mailto|javascript):/i
const IMAGE_FILE_EXT_RE = /\.(png|jpe?g|gif|webp|svg|bmp|ico)$/i

/**
 * Asciidoctor が URI と誤認する `macros:sunset.jpg` 等を相対パスへ。
 * （`:` があると imagesdir が付かず src="macros:..." になる）
 */
export function stripPseudoImageUriScheme(path) {
  if (!path?.trim()) return path ?? ""
  const trimmed = path.trim()
  if (KNOWN_URI_SCHEME_RE.test(trimmed)) return trimmed

  const match = trimmed.match(/^[a-z][a-z0-9+.-]*:(.+)$/i)
  if (!match) return trimmed

  const rest = match[1]
  if (rest.includes("/") || IMAGE_FILE_EXT_RE.test(rest)) return rest
  return trimmed
}

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

/** Propshaft 静的画像（image::/images/filename[] → app/assets/images/filename） */
export function appImageSrc(src) {
  if (!src?.trim()) return null
  const match = src.trim().match(/^\/?images\/(.+)$/i)
  if (!match) return null
  return `/images/${match[1]}`
}

/** `/memos/:id/assets/...` をアセット相対パスへ（imagesdir 二重付与の防止） */
export function memoAssetRelativePath(memoId, src) {
  if (!src?.trim()) return src ?? ""

  const appImage = appImageSrc(src)
  if (appImage) return src.trim()

  const original = src.trim()
  let path = stripPseudoImageUriScheme(original)
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

  path = path.replace(/^\.\//, "")

  return path
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
  if (appImageSrc(filename)) return null
  const relative = memoAssetRelativePath(memoId, filename.trim())
  if (!relative) return null
  return buildMemoAssetSrc(memoId, relative)
}

/** 拡大縮小ビューア（/assets/.../view） */
export function memoAssetViewUrl(memoId, filename) {
  return buildMemoAssetViewUrl(memoAssetSrc(memoId, filename))
}
