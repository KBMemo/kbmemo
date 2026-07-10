# frozen_string_literal: true

require "json"

module Chat
  # ユーザー入力の intent を LFM2.5（ModelRegistry :intent）で分類する（dev note §3.1）。
  # 小型モデルの JSON 崩れに備え、パースは堅牢に（失敗時は unknown / 低 confidence）。
  class IntentClassifier
    INTENTS = %w[
      conversation web_research url_analysis rag_lookup code summarization
      translation image_analysis image_generation memo_search memo_add
      settings_change unknown
    ].freeze

    # system prompt は Chat::Prompts に集約（§3.1）。
    SYSTEM_PROMPT = Chat::Prompts::INTENT_CLASSIFIER

    Result = Struct.new(:intent, :confidence, :needs_tool, :reason, keyword_init: true) do
      def unknown?
        intent == "unknown"
      end
    end

    def initialize(client: nil)
      @client = client
    end

    # @param user_text [String]
    # @param account [Account, nil]
    # @param stream [Boolean]
    # @yield [Hash] { content:, thinking: }
    # @return [Chat::IntentClassifier::Result]
    def classify(user_text, account: nil, stream: false, &block)
      text = user_text.to_s.strip
      return fallback("入力が空です。") if text.blank?

      messages = [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: text }
      ]
      raw = if stream
        client(account).chat(
          messages,
          response_format: { "type" => "json_object" },
          stream: true,
          &block
        )
      else
        client(account).chat(
          messages,
          response_format: { "type" => "json_object" }
        )
      end
      build_result(parse_json(raw))
    rescue Chat::LlmClient::Error, JSON::ParserError => e
      fallback("分類に失敗しました: #{e.message}")
    end

    private

    def client(account)
      @client || Chat::ModelRegistry.for(:intent, account: account).build_client
    end

    # コードフェンスや前後の説明文が混じっても最初の JSON オブジェクトを取り出す。
    def parse_json(raw)
      text = raw.to_s
      candidate = text[/\{.*\}/m] || text
      JSON.parse(candidate)
    end

    def build_result(data)
      return fallback("JSON が不正です。") unless data.is_a?(Hash)

      intent = data["intent"].to_s.strip
      intent = "unknown" unless INTENTS.include?(intent)

      Result.new(
        intent: intent,
        confidence: clamp_confidence(data["confidence"]),
        needs_tool: to_bool(data["needs_tool"]),
        reason: data["reason"].to_s.strip
      )
    end

    def clamp_confidence(value)
      f = Float(value)
      f.clamp(0.0, 1.0)
    rescue ArgumentError, TypeError
      0.0
    end

    def to_bool(value)
      return value if value == true || value == false

      %w[true 1 yes].include?(value.to_s.strip.downcase)
    end

    def fallback(reason)
      Result.new(intent: "unknown", confidence: 0.0, needs_tool: false, reason: reason)
    end
  end
end
