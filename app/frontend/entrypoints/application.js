import "../styles/application.css"

import "@hotwired/turbo-rails"
import "../../javascript/controllers"
import { initUserInvalidAriaSync } from "../../javascript/forms/user_invalid_aria.js"
import { highlightMemoBodies } from "../../javascript/memo_body_highlight.js"
import { applyStoredThemeWithSync, bootstrapAccountTheme, initThemeSync } from "../../javascript/theme/theme_bootstrap.js"
import { applyStoredSkin } from "../../javascript/theme/memo_skins.js"
import {
  applyOpenDirectoryIds,
  loadOpenDirectoryIds,
  syncOpenDirectoryIdsFromPanel
} from "../../javascript/memo_directory_nav_open.js"
import { createIcons, ArrowLeft, BookOpen, CircleHelp, Copy, Eye, GripVertical, Kanban, Link2, PanelLeftOpen, Pencil, Plus, Trash2 } from "lucide"

function accountThemeFromJsonScript() {
  const el = document.getElementById("kbmemo-account-theme-json")
  if (!el?.textContent?.trim()) return null

  try {
    const parsed = JSON.parse(el.textContent)
    return parsed && typeof parsed === "object" ? parsed : null
  } catch {
    return null
  }
}

const renderLucideIcons = () => {
  createIcons({
    icons: {
      ArrowLeft,
      BookOpen,
      CircleHelp,
      Copy,
      Eye,
      GripVertical,
      Kanban,
      Link2,
      PanelLeftOpen,
      Pencil,
      Plus,
      Trash2
    }
  })
}

function refreshCsrfFromResponse(response) {
  const token = response.headers.get("X-CSRF-Token")
  if (!token) return
  const meta = document.querySelector('meta[name="csrf-token"]')
  if (meta) meta.setAttribute("content", token)
  // fetch 自動保存のあと form submit（コミット等）が古い hidden token を送らないよう同期する
  document.querySelectorAll('input[name="authenticity_token"]').forEach((input) => {
    input.value = token
  })
}

document.addEventListener("turbo:before-fetch-response", (event) => {
  const response = event.detail?.fetchResponse?.response
  if (response) refreshCsrfFromResponse(response)
})

const nativeFetch = window.fetch.bind(window)
window.fetch = async (...args) => {
  const response = await nativeFetch(...args)
  refreshCsrfFromResponse(response)
  return response
}

document.addEventListener("turbo:load", renderLucideIcons)
document.addEventListener("turbo:render", renderLucideIcons)
document.addEventListener("turbo:load", () => highlightMemoBodies())
document.addEventListener("turbo:render", () => highlightMemoBodies())
document.addEventListener("turbo:load", () => {
  initThemeSync()
  applyStoredSkin()
  applyStoredThemeWithSync().finally(() => applyStoredSkin())
})
document.addEventListener("turbo:render", () => {
  applyStoredSkin()
  applyStoredThemeWithSync().finally(() => applyStoredSkin())
})

const accountTheme = accountThemeFromJsonScript()
if (accountTheme) bootstrapAccountTheme(accountTheme)
initUserInvalidAriaSync()

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

function historySidebarVisit(url) {
  try {
    return new URL(url, window.location.origin).searchParams.get("sidebar_view") === "history"
  } catch {
    return false
  }
}

function openMemoIdFromUrl(url) {
  try {
    const match = new URL(url, window.location.origin).pathname.match(/\/memos\/(\d+)/)
    return match ? match[1] : null
  } catch {
    return null
  }
}

function sidebarRowIds(container) {
  if (!container) return ""
  return [...container.querySelectorAll("#memo_sidebar_memo_list > li[id^='sidebar_row_memo_']")]
    .map((li) => {
      const match = li.id.match(/^sidebar_row_memo_(.+)$/)
      return match ? match[1] : ""
    })
    .filter(Boolean)
    .join(",")
}

let historySidebarAbortController = null

async function refreshHistoryMemoListFromServer() {
  if (!historySidebarVisit(window.location.href)) return

  historySidebarAbortController?.abort()
  historySidebarAbortController = new AbortController()
  const { signal } = historySidebarAbortController

  const params = new URLSearchParams({ sidebar_view: "history" })
  const openMemoId = openMemoIdFromUrl(window.location.href)
  if (openMemoId) params.set("open_memo_id", openMemoId)

  let response
  try {
    response = await fetch(`/memos/sidebar_memo_list?${params}`, {
      headers: { Accept: "text/html", "X-Kbmemo-Sidebar-Sync": "1" },
      credentials: "same-origin",
      cache: "no-store",
      signal
    })
  } catch (error) {
    if (error.name === "AbortError") return
    throw error
  }

  if (!response.ok) return

  const html = await response.text()
  const doc = new DOMParser().parseFromString(html, "text/html")
  const newContainer = doc.getElementById("memo_sidebar_memo_list_container")
  const currentContainer = document.getElementById("memo_sidebar_memo_list_container")
  if (!newContainer || !currentContainer) return

  const expectedIds =
    newContainer.querySelector("#memo_sidebar_memo_list")?.dataset?.historyMemoIds ??
    sidebarRowIds(newContainer)
  const currentIds = sidebarRowIds(currentContainer)
  if (expectedIds !== "" && currentIds === expectedIds) return

  currentContainer.replaceWith(document.importNode(newContainer, true))
  renderLucideIcons()
}

document.addEventListener("turbo:before-visit", () => {
  historySidebarAbortController?.abort()
})

document.addEventListener("turbo:load", () => {
  refreshHistoryMemoListFromServer()
})

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
        highlightMemoBodies()
      })
    })
    return result
  }
})
