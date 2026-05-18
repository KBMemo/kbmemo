import "../styles/application.css"

import "@hotwired/turbo-rails"
import "../../javascript/controllers"
import { createIcons, BookOpen, CircleHelp, Copy, Eye, GripVertical } from "lucide"

const renderLucideIcons = () => {
  createIcons({
    icons: {
      BookOpen,
      CircleHelp,
      Copy,
      Eye,
      GripVertical
    }
  })
}

document.addEventListener("turbo:load", renderLucideIcons)
document.addEventListener("turbo:render", renderLucideIcons)

// Turbo Stream 置換では turbo:render が来ない。before-stream-render で render を包み、
// DOM 更新後に Lucide を掛け直す（renderStreamMessage は getter のみで上書き不可）。
let lucideAfterStreamFrame = null
const scheduleLucideIconsAfterStream = () => {
  if (lucideAfterStreamFrame != null) cancelAnimationFrame(lucideAfterStreamFrame)
  lucideAfterStreamFrame = requestAnimationFrame(() => {
    lucideAfterStreamFrame = null
    renderLucideIcons()
  })
}

let memosEditorScrollTop = null

function memoStreamTargetId(streamElement) {
  const target = streamElement?.getAttribute?.("target")
  return target?.startsWith("memo_") ? target : null
}

function captureMemosEditorScroll() {
  const el = document.getElementById("memos_editor_scroll")
  if (!el) return
  memosEditorScrollTop = el.scrollTop
}

function restoreMemosEditorScroll() {
  if (memosEditorScrollTop == null) return
  const el = document.getElementById("memos_editor_scroll")
  if (!el) return
  el.scrollTop = memosEditorScrollTop
  memosEditorScrollTop = null
}

document.addEventListener("turbo:before-stream-render", (event) => {
  const streamElement = event.target
  if (streamElement?.tagName === "TURBO-STREAM" && memoStreamTargetId(streamElement)) {
    captureMemosEditorScroll()
  }

  const orig = event.detail?.render
  if (typeof orig !== "function") return

  event.detail.render = (streamElement) => {
    const result = orig(streamElement)
    Promise.resolve(result).finally(() => {
      queueMicrotask(() => {
        if (memoStreamTargetId(streamElement)) {
          restoreMemosEditorScroll()
        }
        scheduleLucideIconsAfterStream()
      })
    })
    return result
  }
})
