// AI チャット応答向けの軽量 Markdown → DOM 変換（XSS 対策のため DOM API のみ使用）。

const INLINE_PATTERN =
  /(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`|\[[^\]]+\]\([^)]+\))/g

export function appendChatMarkdown(container, markdown) {
  container.classList.add("kb-ai-markdown")
  for (const block of parseBlocks(markdown)) {
    container.append(renderBlock(block))
  }
}

function parseBlocks(text) {
  const lines = String(text ?? "").split("\n")
  const blocks = []
  let list = null

  const flushList = () => {
    if (!list) return
    blocks.push(list)
    list = null
  }

  for (const line of lines) {
    if (/^### /.test(line)) {
      flushList()
      blocks.push({ type: "h3", text: line.slice(4) })
      continue
    }
    if (/^## /.test(line)) {
      flushList()
      blocks.push({ type: "h2", text: line.slice(3) })
      continue
    }
    if (/^# /.test(line)) {
      flushList()
      blocks.push({ type: "h1", text: line.slice(2) })
      continue
    }
    if (/^[-*] /.test(line)) {
      if (!list || list.type !== "ul") {
        flushList()
        list = { type: "ul", items: [] }
      }
      list.items.push(line.slice(2))
      continue
    }
    if (/^\d+\. /.test(line)) {
      if (!list || list.type !== "ol") {
        flushList()
        list = { type: "ol", items: [] }
      }
      list.items.push(line.replace(/^\d+\. /, ""))
      continue
    }
    if (line.trim() === "") {
      flushList()
      continue
    }

    flushList()
    blocks.push({ type: "p", text: line })
  }

  flushList()
  return blocks
}

function renderBlock(block) {
  if (block.type === "ul" || block.type === "ol") {
    const list = document.createElement(block.type)
    for (const item of block.items) {
      const li = document.createElement("li")
      appendInline(li, item)
      list.append(li)
    }
    return list
  }

  const element = document.createElement(block.type)
  appendInline(element, block.text)
  return element
}

function appendInline(parent, text) {
  const source = String(text ?? "")
  if (!source) return

  let lastIndex = 0
  for (const match of source.matchAll(INLINE_PATTERN)) {
    const index = match.index ?? 0
    if (index > lastIndex) {
      parent.append(document.createTextNode(source.slice(lastIndex, index)))
    }
    parent.append(renderInlineToken(match[0]))
    lastIndex = index + match[0].length
  }

  if (lastIndex < source.length) {
    parent.append(document.createTextNode(source.slice(lastIndex)))
  }
}

function renderInlineToken(token) {
  if (token.startsWith("**") && token.endsWith("**")) {
    const strong = document.createElement("strong")
    strong.textContent = token.slice(2, -2)
    return strong
  }

  if (token.startsWith("*") && token.endsWith("*")) {
    const em = document.createElement("em")
    em.textContent = token.slice(1, -1)
    return em
  }

  if (token.startsWith("`") && token.endsWith("`")) {
    const code = document.createElement("code")
    code.textContent = token.slice(1, -1)
    return code
  }

  const linkMatch = token.match(/^\[([^\]]+)\]\(([^)]+)\)$/)
  if (linkMatch) {
    const href = sanitizeHref(linkMatch[2])
    if (!href) return document.createTextNode(linkMatch[1])

    const anchor = document.createElement("a")
    anchor.href = href
    anchor.textContent = linkMatch[1]
    anchor.rel = "noopener noreferrer"
    anchor.target = "_blank"
    anchor.className = "kb-chrome-link underline"
    return anchor
  }

  return document.createTextNode(token)
}

function sanitizeHref(raw) {
  const href = String(raw ?? "").trim()
  if (/^https?:\/\//i.test(href)) return href
  return null
}
