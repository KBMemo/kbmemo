import "../styles/application.css"

import "@hotwired/turbo-rails"
import "../../javascript/controllers"
import { applyStoredTheme } from "../../javascript/theme/theme.js"
import {
  applyOpenDirectoryIds,
  loadOpenDirectoryIds,
  syncOpenDirectoryIdsFromPanel
} from "../../javascript/memo_directory_nav_open.js"
import { createIcons, BookOpen, CircleHelp, Copy, Eye, GripVertical, PanelLeftOpen, Pencil, Plus, Trash2 } from "lucide"

const renderLucideIcons = () => {
  createIcons({
    icons: {
      BookOpen,
      CircleHelp,
      Copy,
      Eye,
      GripVertical,
      PanelLeftOpen,
      Pencil,
      Plus,
      Trash2
    }
  })
}

document.addEventListener("turbo:load", renderLucideIcons)
document.addEventListener("turbo:render", renderLucideIcons)
document.addEventListener("turbo:load", applyStoredTheme)
document.addEventListener("turbo:render", applyStoredTheme)

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
  const streamTarget = streamElement?.getAttribute?.("target")
  if (streamElement?.tagName === "TURBO-STREAM" && memoStreamTargetId(streamElement)) {
    captureMemosEditorScroll()
  }
  if (streamTarget === "memos_list_panel") {
    syncOpenDirectoryIdsFromPanel()
  }

  const orig = event.detail?.render
  if (typeof orig !== "function") return

  event.detail.render = (streamElement) => {
    const result = orig(streamElement)
    Promise.resolve(result).finally(() => {
      queueMicrotask(() => {
        const target = streamElement?.getAttribute?.("target")
        if (memoStreamTargetId(streamElement)) {
          restoreMemosEditorScroll()
        }
        if (target === "memos_list_panel") {
          applyOpenDirectoryIds(loadOpenDirectoryIds())
        }
        scheduleLucideIconsAfterStream()
      })
    })
    return result
  }
})
