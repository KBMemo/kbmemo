# Agent guide (kbmemo_site)

このリポジトリでエージェント／コントリビュータが参照する方針の入口です。

## メモ本文

- **正は DB の AsciiDoc プレーン文字列／CM は見せ方のみ。** サーバー側の変換・表示は Asciidoctor（`MemoWikiLinks` 等）。

## Slim と Tailwind

- Slim のドット記法（`tag.foo.bar`）は **`[` を含むクラス名をパースできない**（任意値 `text-[10px]` など）。角括弧付きユーティリティは **`class="クラス名 ..."`** で指定すること。

## Stack (short)

- Rails 8, Rodauth, Pundit, Turbo, Stimulus, Vite
- メモ本文: AsciiDoc（サーバーは Asciidoctor）、Git 作業ツリーは `MemoRepository`
