# kbmemo_site

KBMemo (Kanban + Blog + Memo) のアプリサイト。

## Documentation

| Document | Description |
|----------|-------------|
| [docs/architecture/google-calendar-sync.adoc](docs/architecture/google-calendar-sync.adoc) | Google Calendar 同期（Phase 1） |
| [docs/architecture/database.adoc](docs/architecture/database.adoc) | PostgreSQL・credentials・旧 SQLite インポート |
| [docs/deployment/production.adoc](docs/deployment/production.adoc) | 本番デプロイ手順（Ubuntu 24.04 + nginx、https://kbmemo.net） |
| [docs/architecture/memo-properties.adoc](docs/architecture/memo-properties.adoc) | メモ `properties` JSON の設計方針 |
| [docs/architecture/memo-directory-layout.adoc](docs/architecture/memo-directory-layout.adoc) | メモディレクトリ階層と Git パス |
| [docs/architecture/kanban-mvp.adoc](docs/architecture/kanban-mvp.adoc) | カンバン MVP 仕様 |
| [docs/architecture/memo-body-editor-roadmap.adoc](docs/architecture/memo-body-editor-roadmap.adoc) | 本文 CodeMirror / AsciiDoc エディタの作成指針・ロードマップ |
| [docs/architecture/memo-adoc-passthrough-restriction.adoc](docs/architecture/memo-adoc-passthrough-restriction.adoc) | メモ表示・プレビュー時の AsciiDoc passthrough 制限（XSS 対策） |

## メモ本文のセキュリティ

AsciiDoc の passthrough（`++++` ブロック、`pass:[]` / `+++…+++` インライン）は HTML をそのまま出力する。
KBMemo では **DB 上のソースは変更せず**、メモ show・ライブプレビュー・WYSIWYG プレビューの変換直前で無害化する（literal 化またはエスケープ）。
詳細は [memo-adoc-passthrough-restriction.adoc](docs/architecture/memo-adoc-passthrough-restriction.adoc)。

エージェント向けの入口: [AGENTS.md](AGENTS.md)
