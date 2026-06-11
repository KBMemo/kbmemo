import { existsSync, readFileSync, statSync } from "node:fs"
import { dirname, join } from "node:path"
import { gzipSync } from "node:zlib"

const DEFAULT_MANIFEST = "public/vite-dev/.vite/manifest.json"
const DEFAULT_LIMIT_KB = 500

function argValue(name, fallback) {
  const prefix = `${name}=`
  const inline = process.argv.find((arg) => arg.startsWith(prefix))
  if (inline) return inline.slice(prefix.length)

  const index = process.argv.indexOf(name)
  if (index !== -1 && process.argv[index + 1]) return process.argv[index + 1]

  return fallback
}

function hasFlag(name) {
  return process.argv.includes(name)
}

function listArgValue(name) {
  return argValue(name, "")
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean)
}

function formatKb(bytes) {
  return `${(bytes / 1024).toFixed(2)} kB`
}

function kindFor(entry) {
  if (entry.isEntry) return "entry"
  if (entry.isDynamicEntry) return "dynamic"
  return "asset"
}

function readManifest(path) {
  if (!existsSync(path)) {
    throw new Error(`Manifest not found: ${path}`)
  }
  return JSON.parse(readFileSync(path, "utf8"))
}

const manifestPath = argValue("--manifest", DEFAULT_MANIFEST)
const limitKb = Number(argValue("--limit-kb", String(DEFAULT_LIMIT_KB)))
const limitBytes = Number.isFinite(limitKb) && limitKb > 0 ? limitKb * 1024 : DEFAULT_LIMIT_KB * 1024
const failOnWarning = hasFlag("--fail-on-warning")
const focusTerms = listArgValue("--focus")
const publicRoot = join(dirname(manifestPath), "..")
const manifest = readManifest(manifestPath)

const rows = Object.entries(manifest)
  .filter(([, entry]) => entry.file && /\.(js|css)$/.test(entry.file))
  .map(([source, entry]) => {
    const filePath = join(publicRoot, entry.file)
    const bytes = statSync(filePath).size
    const gzipBytes = gzipSync(readFileSync(filePath)).length
    return {
      source,
      file: entry.file,
      kind: kindFor(entry),
      bytes,
      gzipBytes,
    }
  })
  .filter((row) => {
    if (focusTerms.length === 0) return true

    const haystack = `${row.source} ${row.file}`.toLowerCase()
    return focusTerms.some((term) => haystack.includes(term))
  })
  .sort((a, b) => b.bytes - a.bytes)

const oversized = rows.filter((row) => row.bytes >= limitBytes)

console.log(`Vite bundle report: ${manifestPath}`)
console.log(`Warn limit: ${formatKb(limitBytes)}`)
if (focusTerms.length > 0) {
  console.log(`Focus: ${focusTerms.join(", ")}`)
}
console.log("")
console.log("| kind | size | gzip | file | source |")
console.log("| --- | ---: | ---: | --- | --- |")

for (const row of rows) {
  const marker = row.bytes >= limitBytes ? "!" : ""
  console.log(
    `| ${marker}${row.kind} | ${formatKb(row.bytes)} | ${formatKb(row.gzipBytes)} | ${row.file} | ${row.source} |`
  )
}

if (oversized.length > 0) {
  console.log("")
  console.log(`Oversized bundles: ${oversized.length}`)
  for (const row of oversized) {
    console.log(`- ${row.file}: ${formatKb(row.bytes)} (${row.kind})`)
  }
  if (failOnWarning) {
    process.exitCode = 1
  }
}
