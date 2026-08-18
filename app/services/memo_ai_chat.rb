# frozen_string_literal: true

# メモ編集 AI チャット（AsciiDoc 前提・メモ本文をコンテキストに含める）。
#
# バックエンドは既定でローカルモデル（Chat::ModelRegistry.for(:main)）。
# ローカルへ接続できない場合のみ、登録済み OpenAI キー（BYOK）へフォールバックする。
class MemoAiChat
  MAX_BODY_CHARS = 12_000
  MAX_CONTEXT_CHARS = 4_000
  MAX_HISTORY = 12
  MAX_EXISTING_TAGS = 200
  MODEL_ROLES = %i[main fast_chat].freeze
  MODEL_ROLE_LABELS = {
    main: "Main",
    fast_chat: "Fast chat"
  }.freeze
  EDIT_TARGETS = %w[none selection unit section body].freeze
  JSON_RESPONSE_FORMAT = { "type" => "json_object" }.freeze

  OPENAI_BASE_URL = "https://api.openai.com"
  OPENAI_MODEL = "gpt-4o-mini"

  def initialize(account:, memo:, messages:, selection: nil, editor_context: nil, model_role: :main,
    existing_tags: [], local_client: nil, byok_client: nil)
    @account = account
    @memo = memo
    @messages = Array(messages)
    @editor_context = normalize_editor_context(editor_context)
    @selection = (@editor_context[:selection].presence || selection.to_s.strip).presence
    @existing_tags = normalize_tags(existing_tags).first(MAX_EXISTING_TAGS)
    @model_role = model_role.to_s.to_sym
    raise ArgumentError, "未対応のモデル用途です。" unless MODEL_ROLES.include?(@model_role)

    @local_client = local_client
    @byok_client = byok_client
  end

  # @return [Hash] { reply:, edit:, backend:, model_role:, model: }
  def call
    messages = build_messages
    raw, backend, model = generate(messages)
    parsed = parse_model_response(raw)
    {
      reply: parsed[:reply],
      edit: parsed[:edit],
      backend: backend,
      model_role: @model_role,
      model: model
    }
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
      [ chat_json(client, messages), :local, local_model ]
    rescue Chat::LlmClient::ConnectionError => e
      fallback_or_raise(messages, e)
    end
  end

  def fallback_or_raise(messages, cause)
    raise unavailable_error(cause) unless byok_available?

    [ chat_json(byok_client, messages), :openai, OPENAI_MODEL ]
  end

  def chat_json(client, messages)
    client.chat(messages, response_format: JSON_RESPONSE_FORMAT)
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
      "必ず JSON オブジェクトだけを返してください。Markdown のコードフェンスは付けないでください。",
      '{"reply":"ユーザー向けの短い説明","edit":{"target":"none|selection|unit|section|body","content":"AsciiDoc"}}',
      "AsciiDoc は edit.content にだけ書いてください（Markdown は使わない）。",
      "見出しは `=` レベル、リストは `.` または `*`、強調は `*bold*`、リンクは `https://…[表示名]` または Wiki リンク `[[メモタイトル]]` / `[[タイトル|表示名]]` を使ってください。",
      "コードブロックが必要なら `[source]` または四連バッククォートを使ってください。",
      "質問・要約・説明だけで本文を変えない依頼は target を none にし、content は空にしてください。",
      "選択範囲の書き換えは selection。カーソル位置の段落・表・箇条書きブロック全体の追記や置換は unit。",
      "カーソル位置の見出し節（その見出しから次の同レベル以上の見出し直前まで）は section。全文の整形や再構成は body。",
      "表や箇条書きの各行への追記・置換は、対象ブロック全体を unit の content として書き直してください。セル座標は指定しないでください。",
      "適用位置はクライアントが決めるので、行番号や文字位置は返さないでください。",
      "タグの追加・変更を依頼された場合は、SNS向けのハッシュタグではなく、徒然のメモ分類用タグとして提案してください。",
      "既存タグに意味が合うものがあれば表記を完全に一致させて優先し、タグ名に `#` を付けないでください。",
      "タグだけを求められた場合は target を none にし、reply にタグ名だけを簡潔に提示してください。"
    ]

    parts << ""
    parts << "現在のメモタイトル: #{@memo.title}"
    parts << "メモ本文（抜粋・未保存の編集を含む）:"
    parts << truncate_body(memo_body)
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

    if (unit = @editor_context[:active_unit]).present?
      parts << ""
      parts << "カーソル位置のブロック (#{unit[:kind].presence || "paragraph"}):"
      parts << truncate_context(unit[:adoc])
    end

    if (section = @editor_context[:section]).present?
      parts << ""
      parts << "カーソル位置の節 (#{section[:heading].presence || "（見出しなし）"}):"
      parts << truncate_context(section[:adoc])
    end

    { role: "system", content: parts.join("\n") }
  end

  def memo_body
    @editor_context[:body].presence || @memo.body.to_s
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

  def parse_model_response(raw)
    data = extract_json(raw)
    unless data.is_a?(Hash)
      return { reply: raw.to_s, edit: none_edit }
    end

    edit = normalize_edit(data["edit"] || data[:edit])
    reply = (data["reply"] || data[:reply]).to_s.strip
    reply = "本文を更新しました。" if reply.blank? && edit[:target] != "none"
    reply = raw.to_s if reply.blank?
    { reply: reply, edit: edit }
  rescue JSON::ParserError
    { reply: raw.to_s, edit: none_edit }
  end

  def extract_json(raw)
    text = raw.to_s
    return if text.blank?

    candidate = text[/\{.*\}/m] || text
    JSON.parse(candidate)
  end

  def normalize_edit(raw)
    return none_edit unless raw.is_a?(Hash)

    target = (raw["target"] || raw[:target]).to_s.strip
    target = "none" unless EDIT_TARGETS.include?(target)
    content = (raw["content"] || raw[:content]).to_s
    content = "" if target == "none"
    { target: target, content: content }
  end

  def none_edit
    { target: "none", content: "" }
  end

  def normalize_editor_context(raw)
    return {} if raw.blank?

    hash = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw
    return {} unless hash.is_a?(Hash)

    data = hash.deep_stringify_keys
    {
      body: data["body"].to_s.presence,
      selection: data["selection"].to_s.strip.presence,
      active_unit: normalize_context_block(data["active_unit"], %w[kind adoc]),
      section: normalize_context_block(data["section"], %w[heading adoc])
    }.compact
  end

  def normalize_context_block(raw, keys)
    return if raw.blank?
    return unless raw.is_a?(Hash)

    block = keys.each_with_object({}) do |key, acc|
      value = raw[key].to_s
      acc[key.to_sym] = value if value.present?
    end
    block.presence
  end

  def truncate_body(body)
    return "（空）" if body.blank?
    return body if body.length <= MAX_BODY_CHARS

    "#{body[0, MAX_BODY_CHARS]}\n\n…（以降 #{body.length - MAX_BODY_CHARS} 文字省略）"
  end

  def truncate_context(text)
    value = text.to_s
    return "（空）" if value.blank?
    return value if value.length <= MAX_CONTEXT_CHARS

    "#{value[0, MAX_CONTEXT_CHARS]}\n\n…（以降 #{value.length - MAX_CONTEXT_CHARS} 文字省略）"
  end

  def normalize_tags(tags)
    Array(tags).filter_map do |tag|
      value = tag.to_s.strip.delete_prefix("#")
      value.presence
    end.uniq(&:downcase)
  end
end
