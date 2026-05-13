import "../styles/application.css"

import "@hotwired/turbo-rails"
import "../../javascript/controllers"
import { createIcons, BookOpen, CircleHelp, Eye, GripVertical } from "lucide"

const renderLucideIcons = () => {
  createIcons({
    icons: {
      BookOpen,
      CircleHelp,
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

document.addEventListener("turbo:before-stream-render", (event) => {
  const orig = event.detail?.render
  if (typeof orig !== "function") return

  event.detail.render = async (streamElement) => {
    await orig(streamElement)
    scheduleLucideIconsAfterStream()
  }
})
