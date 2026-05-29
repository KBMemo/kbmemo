import { describe, expect, it } from "vitest"
import { adocSkinsYamlToVariables } from "../adoc_skin_tokens.js"
import {
  ASCIIDOCTOR_SKIN_PRESETS,
  findAsciiDoctorSkinPreset,
} from "../asciidoctor_skin_presets.js"
import { exportThemeYaml, parseThemeImport } from "../theme_yaml.js"

describe("theme_yaml", () => {
  it("imports flat asciidoctor-skins YAML keys", () => {
    const yaml = `
primarycolor: "#9E9E9E"
secondarycolor: "#ba3925"
linkcolor: "#212121"
white: "#FFFFFF"
`
    const imported = parseThemeImport(yaml)
    expect(imported.variables["--mg-primary"]).toBe("#9E9E9E")
    expect(imported.variables["--mg-secondary"]).toBe("#ba3925")
    expect(imported.variables["--mg-link"]).toBe("#212121")
    expect(imported.variables["--mg-text"]).toBe("#FFFFFF")
  })

  it("imports kbmemo theme YAML with asciidoctor_skins block", () => {
    const yaml = `
kind: kbmemo-theme
name: Test Theme
base: dark
asciidoctor_skins:
  primarycolor: "#f39c12"
  maincolor: "#282c34"
chrome:
  bg-page: "#101010"
`
    const imported = parseThemeImport(yaml)
    expect(imported.label).toBe("Test Theme")
    expect(imported.baseTheme).toBe("dark")
    expect(imported.variables["--mg-primary"]).toBe("#f39c12")
    expect(imported.variables["--mg-surface"]).toBe("#282c34")
    expect(imported.variables["--kb-bg-page"]).toBe("#101010")
  })

  it("exports asciidoctor_skins compatible YAML", () => {
    const yaml = exportThemeYaml({
      id: "custom-1",
      label: "Export Me",
      baseTheme: "default",
      variables: {
        "--mg-primary": "#9E9E9E",
        "--kb-bg-page": "#fafafa",
      },
      rules: [],
    })

    expect(yaml).toContain("asciidoctor_skins:")
    expect(yaml).toContain("primarycolor: #9E9E9E")
    expect(yaml).toContain("chrome:")
    expect(yaml).toContain("bg-page: #fafafa")
  })

  it("maps adocSkinsYamlToVariables directly", () => {
    expect(adocSkinsYamlToVariables({ primarycolor: "#abc" })).toEqual({
      "--mg-primary": "#abc",
    })
  })

  it("ships an expanded set of asciidoctor-skins presets with valid palettes", () => {
    expect(ASCIIDOCTOR_SKIN_PRESETS.length).toBeGreaterThanOrEqual(15)

    const ids = ASCIIDOCTOR_SKIN_PRESETS.map((preset) => preset.id)
    expect(new Set(ids).size).toBe(ids.length)
    for (const id of ["material-grey", "material-blue", "fedora", "ubuntu", "notebook"]) {
      expect(ids).toContain(id)
    }

    for (const preset of ASCIIDOCTOR_SKIN_PRESETS) {
      const vars = adocSkinsYamlToVariables(preset.yaml)
      expect(vars["--mg-primary"]).toMatch(/^#/)
      // 白背景パレットで本文テキストが白へ潰れない
      if (vars["--mg-surface"] === "#FFFFFF") {
        expect(vars["--mg-text"]).not.toBe("#FFFFFF")
      }
    }

    expect(findAsciiDoctorSkinPreset("ubuntu")?.label).toBe("Ubuntu")
  })

  it("derives body text from black before white fallback", () => {
    const vars = adocSkinsYamlToVariables({
      maincolor: "#FFFFFF",
      black: "#000000",
      white: "#FFFFFF",
    })
    expect(vars["--mg-surface"]).toBe("#FFFFFF")
    expect(vars["--mg-text-strong"]).toBe("#000000")
    expect(vars["--mg-text"]).toBe("#000000")
  })
})
