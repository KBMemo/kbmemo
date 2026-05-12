import "../styles/application.css"

import "@hotwired/turbo-rails"
import "../../javascript/controllers"
import { createIcons, BookOpen, CircleHelp, Eye } from "lucide"

const renderLucideIcons = () => {
  createIcons({
    icons: {
      BookOpen,
      CircleHelp,
      Eye
    }
  })
}

document.addEventListener("turbo:load", renderLucideIcons)
document.addEventListener("turbo:render", renderLucideIcons)
