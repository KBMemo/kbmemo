import { appImageSrc, memoAssetRelativePath, memoAssetSrc } from "@kbmemo/adoc-kbmemo"

/**
 * @param {ParentNode} container
 * @param {string | null | undefined} memoId
 */
function resolvePreviewAssetUrl(memoId, raw) {
  if (!raw?.trim()) return null

  const trimmed = raw.trim()
  const appImage = appImageSrc(trimmed)
  if (appImage) {
    return { resolved: appImage, relative: null }
  }

  const relative = memoAssetRelativePath(memoId, trimmed)
  if (relative && relative !== raw.trim()) {
    return { resolved: memoAssetSrc(memoId, relative), relative }
  }

  if (/^(https?:|data:|blob:|\/)/.test(trimmed)) return null

  const resolved = memoAssetSrc(memoId, trimmed)
  return resolved ? { resolved, relative: memoAssetRelativePath(memoId, trimmed) || trimmed } : null
}

export function resolvePreviewImages(container, memoId) {
  container.querySelectorAll("img[src]").forEach((img) => {
    const src = img.getAttribute("src")
    if (!src) return

    const resolved = resolvePreviewAssetUrl(memoId, src)
    if (!resolved) return

    if (resolved.relative) {
      img.setAttribute("data-filename", resolved.relative)
    }
    img.setAttribute("src", resolved.resolved)
  })

  container.querySelectorAll("object[data]").forEach((obj) => {
    const data = obj.getAttribute("data")
    if (!data) return

    const resolved = resolvePreviewAssetUrl(memoId, data)
    if (!resolved) return

    if (resolved.relative) {
      obj.setAttribute("data-filename", resolved.relative)
    }
    obj.setAttribute("data", resolved.resolved)
  })
}
