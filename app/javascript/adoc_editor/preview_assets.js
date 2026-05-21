import { memoAssetRelativePath, memoAssetSrc } from "../memo_body_editor/image_syntax"

/**
 * @param {ParentNode} container
 * @param {string | null | undefined} memoId
 */
export function resolvePreviewImages(container, memoId) {
  container.querySelectorAll("img[src]").forEach((img) => {
    const src = img.getAttribute("src")
    if (!src) return

    const relative = memoAssetRelativePath(memoId, src)
    if (relative && relative !== src) {
      img.setAttribute("data-filename", relative)
    }

    if (/^(https?:|data:|blob:|\/)/.test(src)) return

    const resolved = memoAssetSrc(memoId, src)
    if (resolved) img.setAttribute("src", resolved)
  })
}
