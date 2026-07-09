# frozen_string_literal: true

# メモ編集 AI チャット（AsciiDoc 前提・メモ本文をコンテキストに含める）。
#
# バックエンドは既定でローカルモデル（Chat::ModelRegistry.for(:main)）。
# ローカルへ接続できない場合のみ、登録済み OpenAI キー（BYOK）へフォールバックする。
class MemoAiChat
  MAX_BODY_CHARS = 12_000
  MAX_HISTORY = 12

  OPENAI_BASE_URL = "https://api.openai.com"
  OPENAI_MODEL = "gpt-4o-mini"

  def initialize(account:, memo:, messages:, selection: nil, local_client: nil, byok_client: nil)
    @account = account
    @memo = memo
    @messages = Array(messages)
    @selection = selection.to_s.strip.presence
    @local_client = local_client
    @byok_client = byok_client
  end

  # @return [Hash] { reply: String, backend: Symbol }
  def call
    messages = build_messages
    reply, backend = generate(messages)
    { reply: reply, backend: backend }
  end

  private

  def generate(messages)
    # ローカルクライアント構築（未設定なら KeyError）と応答（未起動なら ConnectionError）は
    # どちらも「ローカル利用不可」として BYOK フォールバックへ回す。
    begin
      client = local_client
    rescue KeyError => e
      return fallback_or_raise(messages, e)
    end

    begin
      [ client.chat(messages), :local ]
    rescue Chat::LlmClient::ConnectionError => e
      fallback_or_raise(messages, e)
    end
  end

  def fallback_or_raise(messages, cause)
    raise unavailable_error(cause) unless byok_available?

    [ byok_client.chat(messages), :openai ]
  end

  def local_client
    @local_client ||= Chat::ModelRegistry.for(:main, account: @account).build_client
  end

  def byok_available?
    @account.openai_api_key.present?
  end

  def byok_client
    @byok_client ||= Chat::LlmClient.new(
      base_url: OPENAI_BASE_URL,
      model: OPENAI_MODEL,
      api_key: @account.openai_api_key
    )
  end

  def unavailable_error(cause)
    Chat::LlmClient::ConnectionError.new(
      "ローカル AI に接続できません。llama-server を起動するか、Chat サーバー設定を確認してください。OpenAI フォールバックにはプロフィールで API キーが必要です。（#{cause.message}）"
    )
  end

  def build_messages
    [ system_message ] + trimmed_history
  end

  def system_message
    parts = [
      "あなたは kbmemo のメモ執筆アシスタントです。",
      "ユーザーがメモ本文に貼り付けられるよう、返答は AsciiDoc のプレーン文字列のみにしてください（Markdown は使わない）。",
      "見出しは `=` レベル、リストは `.` または `*`、強調は `*bold*`、リンクは `https://…[表示名]` または Wiki リンク `[[メモタイトル]]` / `[[タイトル|表示名]]` を使ってください。",
      "コードブロックが必要なら `[source]` または四連バッククォートを使ってください。",
      "説明や前置きは最小限にし、依頼に対する本文案を中心に書いてください。"
    ]

    parts << ""
    parts << "現在のメモタイトル: #{@memo.title}"
    parts << "メモ本文（抜粋）:"
    parts << truncate_body(@memo.body.to_s)

    if @selection
      parts << ""
      parts << "ユーザーがエディタで選択している抜粋:"
      parts << @selection
    end

    { role: "system", content: parts.join("\n") }
  end

  def trimmed_history
    @messages.last(MAX_HISTORY).filter_map do |entry|
      role = entry[:role] || entry["role"]
      content = (entry[:content] || entry["content"]).to_s.strip
      next if content.blank?
      next unless %w[user assistant].include?(role.to_s)

      { role: role.to_s, content: content }
    end
  end

  def truncate_body(body)
    return "（空）" if body.blank?
    return body if body.length <= MAX_BODY_CHARS

    "#{body[0, MAX_BODY_CHARS]}\n\n…（以降 #{body.length - MAX_BODY_CHARS} 文字省略）"
  end
end
