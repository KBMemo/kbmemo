# frozen_string_literal: true

# メモ編集 AI チャット（AsciiDoc 前提・メモ本文をコンテキストに含める）。
#
# バックエンドは既定でローカルモデル（Chat::ModelRegistry.for(:main)）。
# ローカルへ接続できない場合のみ、登録済み OpenAI キー（BYOK）へフォールバックする。
class MemoAiChat
  MAX_BODY_CHARS = 12_000
  MAX_HISTORY = 12
  MAX_EXISTING_TAGS = 200
  MODEL_ROLES = %i[main fast_chat].freeze
  MODEL_ROLE_LABELS = {
    main: "Main",
    fast_chat: "Fast chat"
  }.freeze

  OPENAI_BASE_URL = "https://api.openai.com"
  OPENAI_MODEL = "gpt-4o-mini"

  def initialize(account:, memo:, messages:, selection: nil, model_role: :main, existing_tags: [],
    local_client: nil, byok_client: nil)
    @account = account
    @memo = memo
    @messages = Array(messages)
    @selection = selection.to_s.strip.presence
    @existing_tags = normalize_tags(existing_tags).first(MAX_EXISTING_TAGS)
    @model_role = model_role.to_s.to_sym
    raise ArgumentError, "未対応のモデル用途です。" unless MODEL_ROLES.include?(@model_role)

    @local_client = local_client
    @byok_client = byok_client
  end

  # @return [Hash] { reply: String, backend: Symbol, model_role: Symbol, model: String }
  def call
    messages = build_messages
    reply, backend, model = generate(messages)
    { reply: reply, backend: backend, model_role: @model_role, model: model }
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
      [ client.chat(messages), :local, local_model ]
    rescue Chat::LlmClient::ConnectionError => e
      fallback_or_raise(messages, e)
    end
  end

  def fallback_or_raise(messages, cause)
    raise unavailable_error(cause) unless byok_available?

    [ byok_client.chat(messages), :openai, OPENAI_MODEL ]
  end

  def local_client
    @local_client ||= local_config.build_client
  end

  def local_model
    local_config.model
  end

  def local_config
    @local_config ||= Chat::ModelRegistry.for(@model_role, account: @account)
  end

  def byok_available?
    @account.openai_api_key_decryptable?
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
      "タグの追加・変更を依頼された場合は、SNS向けのハッシュタグではなく、徒然のメモ分類用タグとして提案してください。",
      "既存タグに意味が合うものがあれば表記を完全に一致させて優先し、タグ名に `#` を付けないでください。",
      "タグだけを求められた場合は、説明を付けずタグ名だけを簡潔に提示してください。",
      "説明や前置きは最小限にし、依頼に対する本文案を中心に書いてください。"
    ]

    parts << ""
    parts << "現在のメモタイトル: #{@memo.title}"
    parts << "メモ本文（抜粋）:"
    parts << truncate_body(@memo.body.to_s)
    parts << ""
    parts << "現在のタグ:"
    parts << (@memo.tags.pluck(:name).presence&.join(", ") || "（なし）")
    parts << "既存タグ一覧（利用頻度順）:"
    parts << (@existing_tags.presence&.join(", ") || "（なし）")

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

  def normalize_tags(tags)
    Array(tags).filter_map do |tag|
      value = tag.to_s.strip.delete_prefix("#")
      value.presence
    end.uniq(&:downcase)
  end
end
