const STORAGE_KEY = "kbmemo:memoDirectoryNavOpenIds"

export function openDirectoryIdsFromPanel(panel = document.getElementById("memos_list_panel")) {
  if (!panel) return []
  return [...panel.querySelectorAll('[data-memo-directory-nav-branch][data-memo-directory-nav-open="true"]')]
    .map((el) => el.dataset.memoDirectoryId)
    .filter(Boolean)
}

export function saveOpenDirectoryIds(ids) {
  const unique = [...new Set(ids.map(String))].sort()
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(unique))
}

export function loadOpenDirectoryIds() {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed.map(String) : []
  } catch {
    return []
  }
}

export function applyOpenDirectoryIds(ids, panel = document.getElementById("memos_list_panel")) {
  if (!panel || !ids?.length) return
  const idSet = new Set(ids.map(String))
  for (const el of panel.querySelectorAll("[data-memo-directory-nav-branch]")) {
    setBranchOpen(el, idSet.has(el.dataset.memoDirectoryId))
  }
}

export function syncOpenDirectoryIdsFromPanel() {
  saveOpenDirectoryIds(openDirectoryIdsFromPanel())
}

export function setBranchOpen(branch, open) {
  if (!(branch instanceof HTMLElement)) return

  const expanded = Boolean(open)
  branch.dataset.memoDirectoryNavOpen = String(expanded)
  const button = branch.querySelector(":scope > .memo-directory-nav-summary")
  const children = branch.querySelector(":scope > .kb-tree-children")
  button?.setAttribute("aria-expanded", String(expanded))
  if (children) children.hidden = !expanded
}

export function appendNavOpenDirectoryFields(form) {
  if (!(form instanceof HTMLFormElement)) return

  form.querySelectorAll('input[name="nav_open_directory_ids[]"]').forEach((el) => el.remove())

  for (const id of loadOpenDirectoryIds()) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "nav_open_directory_ids[]"
    input.value = id
    form.append(input)
  }
}
