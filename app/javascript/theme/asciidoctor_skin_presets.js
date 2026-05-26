/** Preset palettes from asciidoctor-skins (gh-pages/css/*.css :root blocks). */

/** @typedef {{ id: string, label: string, source: string, yaml: Record<string, string> }} AsciiDoctorSkinPreset */

/** @type {AsciiDoctorSkinPreset[]} */
export const ASCIIDOCTOR_SKIN_PRESETS = [
  {
    id: "material-grey",
    label: "Material Grey",
    source: "asciidoctor-skins",
    yaml: {
      maincolor: "#FFFFFF",
      primarycolor: "#9E9E9E",
      secondarycolor: "#ba3925",
      tertiarycolor: "#186d7a",
      sidebarbackground: "#212121",
      linkcolor: "#EEEEEE",
      linkcoloralternate: "#f44336",
      white: "#FFFFFF",
      black: "#000000",
    },
  },
  {
    id: "dark",
    label: "Dark",
    source: "asciidoctor-skins",
    yaml: {
      maincolor: "#282c34",
      primarycolor: "#f39c12",
      secondarycolor: "#03a9f4",
      tertiarycolor: "#4db6ac",
      sidebarbackground: "#21252b",
      linkcolor: "#f44336",
      linkcoloralternate: "#ff9800",
      white: "#FFFFFF",
    },
  },
  {
    id: "clean",
    label: "Clean",
    source: "asciidoctor-skins",
    yaml: {
      maincolor: "#FFFFFF",
      primarycolor: "#2c3e50",
      secondarycolor: "#ba3925",
      tertiarycolor: "#186d7a",
      sidebarbackground: "#CCC",
      linkcolor: "#b71c1c",
      linkcoloralternate: "#f44336",
      white: "#FFFFFF",
      black: "#000000",
    },
  },
  {
    id: "tufte",
    label: "Tufte",
    source: "asciidoctor-skins",
    yaml: {
      maincolor: "#fffff8",
      primarycolor: "#111111",
      secondarycolor: "#111111",
      tertiarycolor: "#111111",
      sidebarbackground: "#eeeeee",
      linkcolor: "#111111",
      linkcoloralternate: "#111111",
      white: "#fffff8",
      black: "#111111",
    },
  },
]

/** @param {string} presetId */
export function findAsciiDoctorSkinPreset(presetId) {
  return ASCIIDOCTOR_SKIN_PRESETS.find((preset) => preset.id === presetId) ?? null
}
