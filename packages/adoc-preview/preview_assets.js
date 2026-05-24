import { memoAssetRelativePath, memoAssetSrc } from "@kbmemo/adoc-kbmemo"

/**
 * @param {ParentNode} container
 * @param {string | null | undefined} memoId
 */
function resolvePreviewAssetUrl(memoId, raw) {
  if (!raw?.trim()) return null

  const relative = memoAssetRelativePath(memoId, raw)
  if (relative && relative !== raw.trim()) {
    return { resolved: memoAssetSrc(memoId, relative), relative }
  }

  if (/^(https?:|data:|blob:|\/)/.test(raw)) return null

  const resolved = memoAssetSrc(memoId, raw)
  return resolved ? { resolved, relative: memoAssetRelativePath(memoId, raw) || raw } : null
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
