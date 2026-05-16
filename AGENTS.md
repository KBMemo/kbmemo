# Agent guide (kbmemo_site)

このリポジトリでエージェント／コントリビュータが参照するドキュメントと方針の入口です。

## Architecture docs

| Topic | Document |
|-------|----------|
| メモディレクトリ階層（`home` / `share` / `public`、`full_path`） | [docs/architecture/memo-directory-layout.adoc](docs/architecture/memo-directory-layout.adoc) |
| 本文エディタ（CodeMirror + AsciiDoc）の段階的ロードマップ | [docs/architecture/memo-body-editor-roadmap.adoc](docs/architecture/memo-body-editor-roadmap.adoc) |

メモ本文の編集・WYSIWYG ライト・Wiki 補完を触る前に、**memo-body-editor-roadmap** のフェーズと「正は DB の AsciiDoc プレーン文字列／CM は見せ方のみ」を確認すること。

## Stack (short)

- Rails 8, Rodauth, Pundit, Turbo, Stimulus, Vite
- メモ本文: AsciiDoc（サーバーは Asciidoctor）、Git 作業ツリーは `MemoRepository`
