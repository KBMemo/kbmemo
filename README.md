# KBMemo

KBMemo（徒然）は、メモ、タスク、予定、カンバン、ノートブックをまとめて扱う
Rails アプリケーションです。本文は AsciiDoc を正とし、メモを Git 作業ツリーへ
反映できます。

## 主な機能

- AsciiDoc メモの作成、検索、タグ、ディレクトリ、テンプレート
- タスク・予定とカンバンによる日常作業の管理
- ノートブックによるメモの構造化
- Web クリップと `web-clip` タグの自動付与
- 葛籠（Tsuzura）による画像・メディア管理
- 如意（Nyoy）MCP を利用する AI チャットとメモアシスト

## 関連プロジェクト

- [KBMemo/tsuzura](https://github.com/KBMemo/tsuzura): 葛籠。画像・メディア管理サービス
- [KBMemo/nyoy](https://github.com/KBMemo/nyoy): 如意。Agent Graph、LLM、MCP の統合サービス
- [AdocForge](https://github.com/knb/adocforge): AsciiDoc editor の汎用コンポーネント

## 開発環境

必要なものは Ruby `4.0.3`、Node.js、npm、PostgreSQL です。データベース接続情報は
Rails credentials に保存します。実 credentials や API token を repository に追加しないでください。

```bash
bundle install
npm ci
bin/rails credentials:edit
bin/rails db:prepare
bin/dev
```

`credentials:edit` では `db.development` と `db.test` を
[`config/credentials/db.example.yml`](config/credentials/db.example.yml) と同じ構造で
設定します。既存の SQLite データを移す場合は
[`docs/architecture/database.adoc`](docs/architecture/database.adoc) を参照してください。

## 検証

```bash
bin/rails test
npm run test:packages
bin/ci
```

ブラウザを使う system test は Chrome または Chromium が必要です。

```bash
HEADLESS=1 bin/rails test:system
```

## ドキュメント

- [開発・実装方針](AGENTS.md)
- [データベースと credentials](docs/architecture/database.adoc)
- [本番デプロイ](docs/deployment/production.adoc)
- [メモディレクトリ](docs/architecture/memo-directory-layout.adoc)
- [Web クリップ](docs/architecture/web-clipping.adoc)
- [AsciiDoc エディタ方針](docs/architecture/memo-body-editor-roadmap.adoc)
- [公開準備](docs/publication/github-publication.adoc)

## Contributing and security

Contribution guidelines are in [CONTRIBUTING.md](CONTRIBUTING.md). Do not report security
issues publicly; use the private reporting procedure in [SECURITY.md](SECURITY.md).

KBMemo is released under the [MIT License](LICENSE).
