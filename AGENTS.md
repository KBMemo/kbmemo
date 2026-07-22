# Agent guide (kbmemo_site)

このリポジトリでエージェント／コントリビュータが参照する実装方針です。コードを変更するときは、まず既存のサービス、Stimulus controller、CSS token、テストのパターンを確認してください。

## 現在の構成

- Rails 8.1 / PostgreSQL / Rodauth / Pundit
- Turbo + Stimulus。フロントエンドのビルドは Vite (`vite_rails`)
- View は Slim（一部 Rodauth などに ERB）
- CSS は `app/frontend/styles/` の通常 CSS。**Tailwind CSS は使用していない**
- メモ本文は AsciiDoc。サーバー側は Asciidoctor、ブラウザ側は `@asciidoctor/core`
- エディタは CodeMirror 6 と `packages/adoc-*`（package 名は `@kbmemo/adoc-*`）の npm workspace
- DB 接続情報や秘密情報は Rails credentials で管理
- 本番は nginx + Puma + systemd user service。デプロイ入口は `bin/deploy`

## 主なディレクトリ

- `app/controllers`, `app/models`, `app/policies`, `app/services`: Rails アプリケーション本体
- `app/views`: Slim / ERB view
- `app/frontend/entrypoints`: Vite entrypoint
- `app/frontend/styles`: アプリ共通 CSS、theme、本文 skin、互換ユーティリティ
- `app/javascript/controllers`: Stimulus controller
- `app/javascript/adoc_editor`: kbmemo 固有のエディタ統合
- `app/javascript/lib`: UI から独立した JavaScript helper
- `packages`: 再利用可能な `@kbmemo/adoc-*` npm workspace
- `public/bookmarklets`: Web クリップ用の静的ページと bookmarklet
- `docs/architecture`: 設計、ロードマップ、運用上の判断記録
- `docs/deployment/production.adoc`: 本番構成とデプロイ手順

## CSS と View

- Tailwind の runtime、compiler、設定ファイルはない。Tailwind の導入を前提にしない。
- `themes.css` の semantic token（`--kb-*`）と既存 component class（`kb-*`）を優先する。色や状態表現を view ごとに直接定義しない。
- `utility-compat.css` は、過去の utility class を通常 CSS として明示的に実装した互換レイヤー。未定義 class を追加した場合は `npm run check:utility-compat` で検出する。
- 新しい UI は既存 class の組み合わせで表現し、共通化する価値がある見た目・状態だけを `themes.css` などへ追加する。
- theme は `data-kb-theme` / `data-kb-theme-base`、本文 skin は `data-kb-skin` で切り替える。light 固定の色を持ち込まない。
- Slim のドット記法は単純な class に限る。記号を含む class や動的 class は `class="..."` または `class=` を使う。
- アイコンだけの button には `aria-label` を付け、通常時の枠を消しても `:focus-visible` のフォーカス表示は残す。

## JavaScript

- 画面固有の状態と DOM 操作は Stimulus controller に置く。inline script や view への ad-hoc な event handler 追加は避ける。
- HTTP は既存の CSRF helper と Turbo の動作を確認し、認証方式を独自に増やさない。
- HTML を DOM に挿入する処理では Trusted Types と既存 sanitizer の境界を守る。
- JavaScript unit test は Vitest + happy-dom。対象に近い `test/*.test.js` へ追加する。
- `packages/adoc-*` は site 内でも `@kbmemo/adoc-*` workspace dependency として利用する。公開 API を変更するときは package test、build、consumer への影響を確認する。

## メモと永続化

- 通常メモは `home/u-{id}/YYYY-MM-DD` に自動保存する。公開範囲は `visibility`。詳細は `docs/architecture/memo-directory-layout.adoc`。
- メモ本文の正は DB の AsciiDoc プレーン文字列。Git 作業ツリーへの反映は `MemoRepository` が担当する。
- 試行錯誤しやすいオプション項目は `memos.properties`（JSON）へ置く。専用 DB column は横断検索、固定契約、強い整合性が必要な場合に限る。
- `properties` の読み書きは `MemoPropertyOptions` などの薄い accessor / service に集約する。詳細は `docs/architecture/memo-properties.adoc`。
- DB は PostgreSQL。接続情報は Rails credentials の `db.<environment>`。テンプレートは `config/credentials/db.example.yml`。
- 旧 SQLite import は `bin/rails kbmemo:db:import_sqlite`。詳細は `docs/architecture/database.adoc`。

## AsciiDoc エディタ

- WYSIWYG の編集対象は、各 unit が保持する AsciiDoc source。プレビュー HTML や `contentEditable` の内容を正として逆変換しない。
- 同期と保存は `setUnitAdocSource` / `getUnitAdocSource` を通す。`unitToAsciidoc` は保存済み source から組み立てる。
- `htmlToAsciidoc` は通常 paste などの安全網であり、WYSIWYG document model の代替ではない。
- AsciiDoc passthrough は表示・preview の変換直前に制限する。DB 上の source を破壊的に書き換えない。詳細は `docs/architecture/memo-adoc-passthrough-restriction.adoc`。
- 方針と syntax 対応状況は `docs/architecture/memo-body-editor-roadmap.adoc` と `docs/architecture/asciidoc-syntax-coverage-roadmap.adoc` を参照する。

### AdocForge との統合方針

- 当面は徒然で使い勝手の改善と実運用検証を先行する。ただし、AsciiDoc の解析、編集、補完、ハイライト、preview、WYSIWYG などの汎用機能は AdocForge にも同等の機能を取り込む前提で設計する。
- 汎用ロジックを Rails、Stimulus、徒然の DOM、保存 API、theme class に直接依存させない。徒然固有の接続は adapter / controller に置き、AdocForge へ移せる境界を維持する。
- 機能の区切りごとに徒然側の実装と知見を AdocForge へ反映し、公開 API、test、documentation、playground を更新する。徒然だけに汎用機能を長期間 fork した状態で残さない。
- AdocForge 側で必要な機能が揃い、npm package の安定版を公開した段階で、徒然の `@kbmemo/adoc-*` workspace package 利用を `@adocforge/*` package 利用へ切り替える。
- 切り替えは一括置換を前提にせず、対応する AdocForge API、bundle size、browser test、既存メモの互換性を確認しながら段階的に行う。移行完了後、重複する `packages/adoc-*` は互換 adapter を除いて廃止する。

## API と外部連携

- アカウント API トークンは `/api/v1/*` 用。Web クリップトークンは `POST /api/clips` 専用で、複数発行・個別失効できる。用途の異なる token を流用しない。
- Tsuzura は写真・media 管理の別アプリ。連携設計は `docs/architecture/media-platform.adoc`、実装は別 repository の `kbmemo-media`。
- development の Tsuzura endpoint は既定で `http://localhost:3008`。本番接続を試す場合だけ `TSUZURA_*` を明示する。
- Nyoy MCP、Google Calendar、LLM server の設定は既存の account setting / credentials / service class を経由する。

## テストと検証

- Rails test: `bin/rails test`
- 対象 test: `bin/rails test test/path/to/test.rb`
- JavaScript / package test: `npm run test:packages`
- package build: `npm run build:packages`
- CSS utility 整合性: `npm run check:utility-compat`
- bundle budget: `npm run check:bundle-budget`
- 全体確認: `bin/ci`

変更のリスクに応じて対象 test を先に実行し、完了前に原則 `bin/ci` を通す。system test は標準 CI に含まれないため、ブラウザ操作を変更した場合は必要に応じて `bin/rails test:system` または実ブラウザで確認する。

## Migration とセキュリティ

- migration は既存データの移行を含めて設計し、可能なら `db:migrate:redo VERSION=...` で往復を確認する。
- token、API key、credentials の平文を log、fixture、commit に残さない。発行 token は一度だけ表示し、DB には digest を保存する。
- メモ本文、SVG、Markdown、外部 HTML は既存 sanitizer と Trusted Types の境界を迂回しない。
- 認可対象の record は必ず現在の account / policy scope から取得する。

## デプロイ

- 本番手順の正は `docs/deployment/production.adoc`。
- `bin/deploy` は pull、依存更新、migration、Vite / Rails asset build、systemd user service restart、health check を行う。
- service 操作は `systemctl --user` を使う。system service 前提の command を追加しない。
- deploy script を変更した場合は `bin/deploy --dry-run` と shell syntax を確認する。
