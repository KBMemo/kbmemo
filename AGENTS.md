# Agent guide (kbmemo_site)

このリポジトリでエージェント／コントリビュータが参照する方針の入口です。

## メモ本文

- **正は DB の AsciiDoc プレーン文字列／CM は見せ方のみ。** サーバー側の変換・表示は Asciidoctor（`MemoWikiLinks` 等）。

## メモ properties（オプション項目）

- **試行錯誤しやすいオプション項目の正は `memos.properties`（JSON）。** 専用 DB カラムは、横断検索・契約固定・強い整合性が必要になるまで増やさない。
- 読み書きは `properties` を直接散在させず、`MemoPropertyOptions` 等の **薄いアクセサ / サービス** に集約する。
- **DB 接続情報** も環境変数ではなく **Rails credentials**（`db.<env>`）。テンプレート `config/credentials/db.example.yml`
- 詳細・登録済みキー一覧: `docs/architecture/memo-properties.adoc`
- DB セットアップ・旧 SQLite インポート: `docs/architecture/database.adoc`

## WYSIWYG ブロック編集（`@kbmemo/adoc-wysiwyg`）

- **編集対象は AsciiDoc ソース（ユニット内 CodeMirror）のみ。** Asciidoctor が出力したプレビュー HTML は表示用。contentEditable や HTML 逆変換で本文を書き換えない。
- **同期・保存はユニットごとの保存済み AsciiDoc**（`setUnitAdocSource` / `getUnitAdocSource`）。`.wysiwyg-unit` からドキュメントを組み立てるとき HTML から復元しない（`unitToAsciidoc` は stored source のみ返す）。
- `htmlToAsciidoc` の段落シリアライズ（`+` / `[%hardbreaks]` / `[.lead]` 等）は **非 WYSIWYG 向けの安全網**。Block WYSIWYG の記法対応を足すときも、この方針を崩さない。
- 詳細: `docs/architecture/memo-body-editor-roadmap.adoc`（Phase 6c — 基本方針）

## Slim と Tailwind

- Slim のドット記法（`tag.foo.bar`）は **`[` を含むクラス名をパースできない**（任意値 `text-[10px]` など）。角括弧付きユーティリティは **`class="クラス名 ..."`** で指定すること。

## Tsuzura（写真・media.kbmemo.net）

- Phase 1 完了（CLI + `album::` / `image::media:` 表示）。**Phase 2 準備:** `docs/architecture/tsuzura-phase2.adoc`
- 全体設計: `docs/architecture/media-platform.adoc`。実装リポジトリ: `kbmemo-media`（別 clone）

## Stack (short)

- Rails 8, Rodauth, Pundit, Turbo, Stimulus, Vite
- DB: PostgreSQL。接続情報は **Rails credentials**（`db.development` / `db.test` / `db.production`）。テンプレート `config/credentials/db.example.yml`
- 旧 SQLite 移行: `bin/rails kbmemo:db:import_sqlite`（`docs/architecture/database.adoc`）
- メモ本文: AsciiDoc（サーバーは Asciidoctor）、Git 作業ツリーは `MemoRepository`
