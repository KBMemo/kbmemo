// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from "vitest"
import {
  applySkin,
  applyStoredSkin,
  getStoredSkinId,
  listAvailableSkins,
} from "../memo_skins.js"
import {
  createCustomSkin,
  deleteCustomSkin,
  findCustomSkin,
  loadThemeStorage,
  THEME_STORAGE_KEY,
  upsertCustomSkin,
} from "../theme_storage.js"

beforeEach(() => {
  localStorage.clear()
  delete document.documentElement.dataset.kbSkin
  document.getElementById("kbmemo-custom-skin-style")?.remove()
})

describe("memo_skins", () => {
  it("defaults to auto when nothing is stored", () => {
    expect(getStoredSkinId()).toBe("auto")
  })

  it("applies a builtin skin and persists it", () => {
    const applied = applySkin("github")
    expect(applied).toBe("github")
    expect(document.documentElement.dataset.kbSkin).toBe("github")
    expect(getStoredSkinId()).toBe("github")
    expect(loadThemeStorage().activeSkinId).toBe("github")
  })

  it("falls back to auto for an unknown skin id", () => {
    expect(applySkin("does-not-exist")).toBe("auto")
    expect(document.documentElement.dataset.kbSkin).toBe("auto")
  })

  it("keeps theme fields intact when changing the skin", () => {
    localStorage.setItem(
      THEME_STORAGE_KEY,
      JSON.stringify({ activeThemeId: "dark", customThemes: [] })
    )
    applySkin("github")
    const state = loadThemeStorage()
    expect(state.activeThemeId).toBe("dark")
    expect(state.activeSkinId).toBe("github")
  })

  it("injects and removes a custom skin style element", () => {
    const skin = upsertCustomSkin(
      createCustomSkin({ label: "Mine", css: ".memo-body{color:red}" })
    )
    expect(findCustomSkin(skin.id)).not.toBeNull()

    applySkin(skin.id)
    const styleEl = document.getElementById("kbmemo-custom-skin-style")
    expect(styleEl).not.toBeNull()
    expect(styleEl.textContent).toContain(".memo-body{color:red}")

    applySkin("auto")
    expect(document.getElementById("kbmemo-custom-skin-style")).toBeNull()
  })

  it("lists builtin and custom skins together", () => {
    upsertCustomSkin(createCustomSkin({ label: "Mine", css: "" }))
    const skins = listAvailableSkins()
    expect(skins.map((s) => s.id)).toContain("auto")
    expect(skins.map((s) => s.id)).toContain("github")
    expect(skins.some((s) => !s.builtin)).toBe(true)
  })

  it("resets active skin to auto when the active custom skin is deleted", () => {
    const skin = upsertCustomSkin(createCustomSkin({ label: "Mine", css: "" }))
    applySkin(skin.id)
    deleteCustomSkin(skin.id)
    expect(loadThemeStorage().activeSkinId).toBe("auto")
    expect(applyStoredSkin()).toBe("auto")
  })
})
