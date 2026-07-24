import { Controller } from "@hotwired/stimulus"

function linksWithin(root) {
  if (!(root instanceof Element)) return []
  return root.matches("a[href]") ? [root, ...root.querySelectorAll("a[href]")] :
    [...root.querySelectorAll("a[href]")]
}

export function openExternalLinksInNewTabs(root, currentOrigin = window.location.origin) {
  for (const link of linksWithin(root)) {
    let url
    try {
      url = new URL(link.href, window.location.href)
    } catch {
      continue
    }

    if (!["http:", "https:"].includes(url.protocol) || url.origin === currentOrigin) continue

    link.target = "_blank"
    const rel = new Set(link.rel.split(/\s+/).filter(Boolean))
    rel.add("noopener")
    link.rel = [...rel].join(" ")
  }
}

export default class extends Controller {
  connect() {
    openExternalLinksInNewTabs(this.element)
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "attributes") {
          openExternalLinksInNewTabs(mutation.target)
          continue
        }
        mutation.addedNodes.forEach((node) => openExternalLinksInNewTabs(node))
      }
    })
    this.observer.observe(this.element, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["href"]
    })
  }

  disconnect() {
    this.observer?.disconnect()
  }
}
