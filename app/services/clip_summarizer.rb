# frozen_string_literal: true

class ClipSummarizer
  MAX_CONTENT_LENGTH = 48_000
  SYSTEM_PROMPT = <<~PROMPT
    あなたはWebページ本文の要約器です。
    与えられた本文だけを根拠に、日本語のAsciiDoc形式で要約してください。

    出力:
    * 冒頭に3行以内の概要
    * 続けて「== 重要ポイント」の箇条書き
    * 必要なら「== 詳細」セクション

    制約:
    * Markdownの見出しやコードフェンスを使わない
    * 本文にない情報を追加しない
    * 広告、ナビゲーション、重複表現を無視する
    * 出力は要約本文だけにする
  PROMPT

  class Error < StandardError; end

  class << self
    def call(account:, content:)
      text = content.to_s.strip
      raise Error, "要約対象の本文が空です。" if text.blank?

      client = Chat::ModelRegistry.for(:fast_chat, account: account).build_client
      reply = client.chat(
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: text.first(MAX_CONTENT_LENGTH) }
        ],
        temperature: 0.2
      )
      strip_code_fence(reply)
    rescue Chat::LlmClient::Error, KeyError, ArgumentError => e
      raise Error, "サマリーを生成できませんでした: #{e.message}"
    end

    private

    def strip_code_fence(text)
      text.to_s.strip.sub(/\A```(?:asciidoc|adoc)?\s*/i, "").sub(/\s*```\z/, "").strip
    end
  end
end
