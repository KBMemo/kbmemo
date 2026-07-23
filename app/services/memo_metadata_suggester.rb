# frozen_string_literal: true

class MemoMetadataSuggester
  MAX_BODY_CHARS = 12_000
  MAX_EXISTING_TAGS = 200
  MAX_TAGS = 8

  def initialize(account:, title:, body:, current_tags:, existing_tags:, client: nil)
    @account = account
    @title = title.to_s.strip
    @body = body.to_s.first(MAX_BODY_CHARS)
    @current_tags = normalize_tags(current_tags)
    @existing_tags = normalize_tags(existing_tags).first(MAX_EXISTING_TAGS)
    @client = client
  end

  def call
    raw = client.chat(messages, response_format: { "type" => "json_object" })
    data = JSON.parse(strip_code_fence(raw))

    {
      title: data.fetch("title").to_s.strip.first(200),
      tags: normalize_tags(data["tags"]).first(MAX_TAGS)
    }.tap do |result|
      raise Chat::LlmClient::Error, "AIがタイトルを生成できませんでした。" if result[:title].blank?
    end
  rescue JSON::ParserError, KeyError
    raise Chat::LlmClient::Error, "AIの提案を解析できませんでした。"
  end

  private

  def client
    @client ||= Chat::ModelRegistry.for(:fast_chat, account: @account).build_client
  end

  def messages
    [
      {
        role: "system",
        content: <<~PROMPT
          あなたは日本語メモのタイトルとタグを整理するアシスタントです。
          メモ本文を端的に表すタイトルを1つと、検索・分類に有用なタグを3〜8個提案してください。
          既存タグ一覧に意味が合うタグがあれば、表記を完全に一致させて優先してください。
          ただし、内容に合わない既存タグは使わず、必要なら新しい短いタグを提案してください。
          タグに # を付けないでください。説明やMarkdownは出力しないでください。
          必ず {"title":"...","tags":["..."]} 形式のJSONオブジェクトだけを返してください。
        PROMPT
      },
      {
        role: "user",
        content: <<~CONTENT
          現在のタイトル:
          #{@title.presence || "（未設定）"}

          現在のタグ:
          #{@current_tags.presence&.join(", ") || "（なし）"}

          既存タグ一覧（利用頻度順）:
          #{@existing_tags.presence&.join(", ") || "（なし）"}

          メモ本文:
          #{@body.presence || "（空）"}
        CONTENT
      }
    ]
  end

  def normalize_tags(tags)
    Array(tags).filter_map do |tag|
      value = tag.to_s.strip.delete_prefix("#")
      value.presence
    end.uniq(&:downcase)
  end

  def strip_code_fence(raw)
    raw.to_s.strip.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
  end
end
