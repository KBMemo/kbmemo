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
  EDIT_TARGETS = %w[none selection unit section body].freeze
  JSON_RESPONSE_FORMAT = { "type" => "json_object" }.freeze

  OPENAI_BASE_URL = "https://api.openai.com"
  OPENAI_MODEL = "gpt-4o-mini"

  class << self
    def asciidoc_from_text(text)
      stripped = strip_code_fence(text)
      data = extract_json_object(stripped)
      extracted =
        if schema_payload?(data)
          content = nested_edit_content(data)
          if content.present? && !json_envelope?(content)
            content
          else
            reply = hash_value(data, "reply").to_s.strip
            reply.present? && !json_envelope?(reply) ? reply : ""
          end
        else
          stripped
        end

      coerce_asciidoc(extracted)
    end

    def coerce_asciidoc(text)
      value = text.to_s.gsub("\r\n", "\n").strip
      return value if value.blank? || !looks_like_markdown?(value)

      PandocMarkdownToAsciidoc.convert(value).strip
    rescue PandocRunner::NotFound, PandocRunner::Error
      markdown_to_asciidoc_lite(value)
    end

    def looks_like_markdown?(text)
      value = text.to_s
      return false if value.blank?
      return true if value.match?(/\[[^\]]+\]\([^)\s]+\)/)

      lines = value.each_line
      return true if lines.any? do |line|
        line.match?(/^\#{1,6}\s+\S/) ||
          line.match?(/^\s*```/) ||
          line.match?(/^\s*\|.*-{3,}/)
      end

      has_asciidoc_structure = value.each_line.any? do |line|
        line.match?(/^=+\s+\S/) ||
          line.match?(/^\s*\*\s+\S/) ||
          line.match?(/^\|===/) ||
          line.match?(/^\[source/)
      end
      return false if has_asciidoc_structure

      value.each_line.any? do |line|
        line.match?(/^\s*[-+]\s+\S/) || line.match?(/^\s*\d+\.\s+\S/)
      end
    end

    def markdown_to_asciidoc_lite(text)
      value = convert_fenced_code(text.to_s.gsub("\r\n", "\n"))
      value = value.gsub(/^\#\#\#\#\#\#\s+/m, "====== ")
      value = value.gsub(/^\#\#\#\#\#\s+/m, "===== ")
      value = value.gsub(/^\#\#\#\#\s+/m, "==== ")
      value = value.gsub(/^\#\#\#\s+/m, "=== ")
      value = value.gsub(/^\#\#\s+/m, "== ")
      value = value.gsub(/^\#\s+/m, "= ")
      value = value.gsub(/\[([^\]]+)\]\((https?:[^)\s]+)\)/, '\2[\1]')
      value = value.gsub(/^(\s*)[-+]\s+/m, '\1* ')
      value = value.gsub(/^(\s*)\d+\.\s+/m, '\1. ')
      value = value.gsub(/\*\*(.+?)\*\*/, '*\1*')
      value.strip
    end

    def json_envelope?(text)
      schema_payload?(extract_json_object(text))
    end

    def extract_json_object(raw)
      text = strip_code_fence(raw)
      return if text.blank?

      start = text.index("{")
      return unless start

      candidate = text[start..]
      try_parse_json(candidate) || try_parse_json(repair_json_strings(candidate)) || synthesize_broken_envelope(candidate)
    end

    def try_parse_json(candidate)
      JSON.parse(candidate)
    rescue JSON::ParserError
      snippet = candidate[/\{.*\}/m]
      return if snippet.blank?

      begin
        JSON.parse(snippet)
      rescue JSON::ParserError
        begin
          JSON.parse(repair_json_strings(snippet))
        rescue JSON::ParserError
          nil
        end
      end
    end

    def looks_like_json_envelope?(text)
      value = text.to_s.strip
      value.start_with?("{") && value.match?(/"(?:reply|edit)"\s*:/) && value.match?(/"edit"\s*:/)
    end

    def synthesize_broken_envelope(text)
      return unless looks_like_json_envelope?(text)

      content = extract_broken_content(text)
      reply = extract_broken_reply(text)
      return if content.blank? && reply.blank?

      target = text[/"target"\s*:\s*"(none|selection|unit|section|body)"/, 1] || "none"
      { "reply" => reply.to_s, "edit" => { "target" => target, "content" => content.to_s } }
    end

    def extract_broken_reply(text)
      match = text.to_s[/"reply"\s*:\s*"((?:\\.|[^"\\])*)"/, 1]
      unescape_json_string(match).strip
    end

    def extract_broken_content(text)
      value = text.to_s
      if (closed = value.match(/"content"\s*:\s*"([\s\S]*)"\s*\}\s*\}\s*\z/))
        return unescape_json_string(closed[1]).strip
      end

      open = value.match(/"content"\s*:\s*"/)
      return "" unless open

      rest = value[open.end(0)..]
      unescape_json_string(rest.sub(/"\s*\}[\s\}]*\z/, "")).strip
    end

    def unescape_json_string(value)
      value.to_s
        .gsub('\\n', "\n")
        .gsub('\\t', "\t")
        .gsub('\\r', "\r")
        .gsub('\\"', '"')
        .gsub("\\\\", "\\")
    end

    def repair_json_strings(text)
      out = +""
      in_string = false
      escape = false
      text.to_s.each_char do |ch|
        unless in_string
          out << ch
          in_string = true if ch == '"'
          next
        end

        if escape
          out << ch
          escape = false
          next
        end
        if ch == "\\"
          out << ch
          escape = true
          next
        end
        if ch == '"'
          out << ch
          in_string = false
          next
        end
        if ch == "\n"
          out << "\\n"
          next
        end
        next if ch == "\r"
        if ch == "\t"
          out << "\\t"
          next
        end
        out << ch
      end
      out
    end

    def schema_payload?(data)
      data.is_a?(Hash) && (
        data.key?("reply") || data.key?(:reply) || data.key?("edit") || data.key?(:edit)
      )
    end

    def nested_edit_content(data)
      edit = hash_value(data, "edit")
      content = edit.is_a?(Hash) ? hash_value(edit, "content") : nil
      content.to_s.strip
    end

    def hash_value(data, key)
      return unless data.is_a?(Hash)

      data[key] || data[key.to_sym]
    end

    def strip_code_fence(text)
      text.to_s.strip.sub(/\A```(?:json|markdown|md|asciidoc|adoc)?\s*/i, "").sub(/```\s*\z/, "").strip
    end

    def convert_fenced_code(text)
      text.to_s.gsub(/^```([^\n]*)\n(.*?)^```[ \t]*$/m) do
        language = Regexp.last_match(1).to_s.strip
        body = Regexp.last_match(2).to_s.sub(/\n\z/, "")
        header = language.present? ? "[source,#{language}]" : "[source]"
        "#{header}\n----\n#{body}\n----"
      end
    end
  end

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
      insert_content: parsed[:insert_content],
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
      # llama-server の json_object 制約は巨大プロンプトで生成が止まって ReadTimeout になりやすい。
      # JSON は system prompt と応答パースに任せ、API 側では強制しない。
      [ chat_completion(client, messages), :local, local_model ]
    rescue Chat::LlmClient::ConnectionError => e
      fallback_or_raise(messages, e)
    end
  end

  def fallback_or_raise(messages, cause)
    raise unavailable_error(cause) unless byok_available?

    [ chat_completion(byok_client, messages, json_object: true), :openai, OPENAI_MODEL ]
  end

  def chat_completion(client, messages, json_object: false)
    if json_object
      client.chat(messages, response_format: JSON_RESPONSE_FORMAT)
    else
      client.chat(messages)
    end
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
      parts << "カーソル位置のブロック種別: #{unit[:kind].presence || "paragraph"}"
    end

    if (section = @editor_context[:section]).present?
      parts << ""
      parts << "カーソル位置の節見出し: #{section[:heading].presence || "（見出しなし）"}"
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
    data = self.class.extract_json_object(raw)
    unless self.class.schema_payload?(data)
      insert_content = self.class.asciidoc_from_text(raw)
      return {
        reply: display_reply(raw.to_s, insert_content),
        edit: none_edit,
        insert_content: insert_content
      }
    end

    edit = normalize_edit(data["edit"] || data[:edit])
    reply = (data["reply"] || data[:reply]).to_s.strip
    insert_content = insert_content_for(edit: edit, reply: reply)
    {
      reply: display_reply(reply, insert_content),
      edit: edit,
      insert_content: insert_content
    }
  end

  def insert_content_for(edit:, reply:)
    content = self.class.asciidoc_from_text(edit[:content].to_s)
    return content if content.present?

    fallback = self.class.asciidoc_from_text(reply.to_s)
    return fallback if fallback.present? && !self.class.json_envelope?(fallback)

    ""
  end

  def display_reply(reply, insert_content)
    text = reply.to_s.strip
    return insert_content if text.blank? && insert_content.present?
    return insert_content.presence || "本文案を用意しました。" if self.class.json_envelope?(text)

    text
  end

  def normalize_edit(raw)
    return none_edit unless raw.is_a?(Hash)

    target = (raw["target"] || raw[:target]).to_s.strip
    target = "none" unless EDIT_TARGETS.include?(target)
    content = self.class.coerce_asciidoc((raw["content"] || raw[:content]).to_s)
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

  def normalize_tags(tags)
    Array(tags).filter_map do |tag|
      value = tag.to_s.strip.delete_prefix("#")
      value.presence
    end.uniq(&:downcase)
  end
end
