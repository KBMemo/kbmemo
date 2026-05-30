import { cpSync, existsSync, mkdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const editorRoot = join(root, "node_modules/svgedit/dist/editor")
const destRoot = join(root, "public/svgedit")

if (!existsSync(editorRoot)) {
  console.warn("copy-svgedit-assets: svgedit is not installed; skipping")
  process.exit(0)
}

mkdirSync(destRoot, { recursive: true })

for (const name of ["images", "extensions", "components"]) {
  const from = join(editorRoot, name)
  const to = join(destRoot, name)
  if (!existsSync(from)) continue
  cpSync(from, to, { recursive: true })
}

console.log("copy-svgedit-assets: copied SVGEdit static assets to public/svgedit")
