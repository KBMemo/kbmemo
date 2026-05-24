# @kbmemo/adoc-* packages

AsciiDoc editor packages extracted from [kbmemo](https://gitea.artif.org/Artif.org/kbmemo_site).

| Package | Role |
|---------|------|
| `@kbmemo/adoc-codemirror` | Asciidoctor AST → CodeMirror 6 highlights + edit units |
| `@kbmemo/adoc-preview` | Live HTML preview |
| `@kbmemo/adoc-wysiwyg` | Block WYSIWYG editor |
| `@kbmemo/adoc-kbmemo` | KBMemo extensions (wiki, diagram, math, HostConfig) |
| `@kbmemo/adoc-editor` | Umbrella re-export for external apps |

Current release line: **0.1.0** (all packages share the same version).

## Development (monorepo)

```bash
npm install
npm run build:packages
npm run test:packages
npm run pack:packages
npm run verify:consumer
npm run verify:publish
```

Site dev uses Vite aliases to package sources (`vite.config.ts`). Published tarballs use `dist/`.

## Registry publish (Gitea npm)

1. Copy `.npmrc.example` → `.npmrc` and set credentials:

```bash
export NPM_PUBLISH_REGISTRY=https://gitea.artif.org/api/packages/Artif.org/npm/
export NPM_PUBLISH_REGISTRY_HOST=gitea.artif.org
export NPM_TOKEN=...
```

2. Confirm publish metadata:

```bash
npm run verify:publish
```

3. Dry-run then publish:

```bash
npm run publish:packages -- --dry-run
npm run publish:packages
```

Packages publish in dependency order (`adoc-kbmemo` → … → `adoc-editor`).

## External install

```bash
npm install @kbmemo/adoc-editor @asciidoctor/core @codemirror/state @codemirror/view codemirror highlight.js
```

See `examples/adoc-editor-demo/` and `docs/architecture/memo-body-editor-roadmap.adoc` (npm パッケージ section).
