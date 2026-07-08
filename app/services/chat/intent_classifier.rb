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

    SYSTEM_PROMPT = <<~PROMPT
      あなたはAIチャットアプリのIntent Classifierです。
      ユーザー入力を読み、最も適切なintentを1つだけ選んでください。

      返答はJSONのみです。説明文は不要です。

      intent候補:
      - conversation
      - web_research
      - url_analysis
      - rag_lookup
      - code
      - summarization
      - translation
      - image_analysis
      - image_generation
      - memo_search
      - memo_add
      - settings_change
      - unknown

      出力形式:
      {
        "intent": "...",
        "confidence": 0.0,
        "needs_tool": true,
        "reason": "短い理由"
      }

      判断基準:
      - URLが含まれる場合は url_analysis
      - 最新情報が必要なら web_research
      - アプリ内メモやナレッジ検索が必要なら rag_lookup
      - 画像生成依頼なら image_generation
      - 画像・スクリーンショット解析なら image_analysis
      - コード修正・実装相談なら code
      - 単なる会話なら conversation
    PROMPT

    Result = Struct.new(:intent, :confidence, :needs_tool, :reason, keyword_init: true) do
      def unknown?
        intent == "unknown"
      end
    end

    def initialize(client: nil)
      @client = client
    end

    # @param user_text [String]
    # @return [Chat::IntentClassifier::Result]
    def classify(user_text)
      text = user_text.to_s.strip
      return fallback("入力が空です。") if text.blank?

      raw = client.chat(
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: text }
        ],
        response_format: { "type" => "json_object" }
      )
      build_result(parse_json(raw))
    rescue Chat::LlmClient::Error, JSON::ParserError => e
      fallback("分類に失敗しました: #{e.message}")
    end

    private

    def client
      @client ||= Chat::ModelRegistry.for(:intent).build_client
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
