# Agent guide (kbmemo_site)

このリポジトリでエージェント／コントリビュータが参照する方針の入口です。

## メモ本文

- **正は DB の AsciiDoc プレーン文字列／CM は見せ方のみ。** サーバー側の変換・表示は Asciidoctor（`MemoWikiLinks` 等）。

## WYSIWYG ブロック編集（`@kbmemo/adoc-wysiwyg`）

- **編集対象は AsciiDoc ソース（ユニット内 CodeMirror）のみ。** Asciidoctor が出力したプレビュー HTML は表示用。contentEditable や HTML 逆変換で本文を書き換えない。
- **同期・保存はユニットごとの保存済み AsciiDoc**（`setUnitAdocSource` / `getUnitAdocSource`）。`.wysiwyg-unit` からドキュメントを組み立てるとき HTML から復元しない（`unitToAsciidoc` は stored source のみ返す）。
- `htmlToAsciidoc` の段落シリアライズ（`+` / `[%hardbreaks]` / `[.lead]` 等）は **非 WYSIWYG 向けの安全網**。Block WYSIWYG の記法対応を足すときも、この方針を崩さない。
- 詳細: `docs/architecture/memo-body-editor-roadmap.adoc`（Phase 6c — 基本方針）

## Slim と Tailwind

- Slim のドット記法（`tag.foo.bar`）は **`[` を含むクラス名をパースできない**（任意値 `text-[10px]` など）。角括弧付きユーティリティは **`class="クラス名 ..."`** で指定すること。

## Stack (short)

- Rails 8, Rodauth, Pundit, Turbo, Stimulus, Vite
- メモ本文: AsciiDoc（サーバーは Asciidoctor）、Git 作業ツリーは `MemoRepository`
