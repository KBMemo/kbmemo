import { Controller } from "@hotwired/stimulus"
import {
  applySkin,
  getStoredSkinId,
  listAvailableSkins,
  populateSkinSelect,
} from "../theme/memo_skins.js"
import {
  createCustomSkin,
  deleteCustomSkin,
  findCustomSkin,
  upsertCustomSkin,
} from "../theme/theme_storage.js"

// Theme Studio の「本文スキン」セクション。builtin スキン適用とカスタム CSS スキンの
// 追加・編集・削除を担う（theme-studio コントローラとは独立）。
export default class extends Controller {
  static targets = ["select", "name", "css", "customList", "status"]

  connect() {
    this._editingId = null
    this.refreshSelect()
    this.renderCustomList()
  }

  refreshSelect() {
    if (!this.hasSelectTarget) return
    populateSkinSelect(this.selectTarget)
    this.selectTarget.value = getStoredSkinId()
  }

  applySelected() {
    if (!this.hasSelectTarget) return
    const id = applySkin(this.selectTarget.value)
    this.setStatus(`スキン「${id}」を適用しました`)
  }

  newCustom() {
    this._editingId = null
    if (this.hasNameTarget) this.nameTarget.value = ""
    if (this.hasCssTarget) this.cssTarget.value = ""
    this.setStatus("新規カスタムスキンを入力してください")
  }

  saveCustom() {
    const label = (this.hasNameTarget ? this.nameTarget.value : "").trim()
    const css = this.hasCssTarget ? this.cssTarget.value : ""
    if (!label) {
      this.setStatus("スキン名を入力してください")
      return
    }

    const skin = createCustomSkin({ id: this._editingId ?? undefined, label, css })
    upsertCustomSkin(skin)
    this._editingId = skin.id
    applySkin(skin.id)
    this.refreshSelect()
    this.renderCustomList()
    this.setStatus(`カスタムスキン「${label}」を保存して適用しました`)
  }

  editCustom(event) {
    const id = event.params.skinId
    const skin = findCustomSkin(id)
    if (!skin) return
    this._editingId = id
    if (this.hasNameTarget) this.nameTarget.value = skin.label
    if (this.hasCssTarget) this.cssTarget.value = skin.css
    this.setStatus(`「${skin.label}」を編集中`)
  }

  deleteCustom(event) {
    const id = event.params.skinId
    deleteCustomSkin(id)
    if (this._editingId === id) this.newCustom()
    applySkin(getStoredSkinId())
    this.refreshSelect()
    this.renderCustomList()
    this.setStatus("カスタムスキンを削除しました")
  }

  renderCustomList() {
    if (!this.hasCustomListTarget) return
    const customs = listAvailableSkins().filter((skin) => !skin.builtin)

    if (customs.length === 0) {
      const empty = document.createElement("li")
      empty.className = "text-xs kb-text-muted"
      empty.textContent = "（カスタムスキンはありません）"
      this.customListTarget.replaceChildren(empty)
      return
    }

    this.customListTarget.replaceChildren(
      ...customs.map((skin) => {
        const li = document.createElement("li")
        li.className = "flex items-center justify-between gap-2 text-sm kb-text-primary"

        const name = document.createElement("span")
        name.className = "min-w-0 flex-1 truncate"
        name.textContent = skin.label
        li.appendChild(name)

        li.appendChild(this.actionButton("編集", "editCustom", skin.id))
        li.appendChild(this.actionButton("削除", "deleteCustom", skin.id))
        return li
      })
    )
  }

  actionButton(label, method, skinId) {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = "kb-chrome-btn-secondary shrink-0 px-2 py-0.5 text-xs"
    btn.textContent = label
    btn.setAttribute("data-action", `skin-studio#${method}`)
    btn.setAttribute("data-skin-studio-skin-id-param", skinId)
    return btn
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
