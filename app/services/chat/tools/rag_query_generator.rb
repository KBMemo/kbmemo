# frozen_string_literal: true

require "json"

module Chat
  module Tools
    # ユーザー質問から pgroonga 検索用クエリを生成する（dev note §3.3 / LFM2.5 intent 役割）。
    class RagQueryGenerator
      Result = Struct.new(:queries, :keywords, :requires_recent_info, keyword_init: true)

      def initialize(client: nil)
        @client = client
      end

      # @param user_text [String]
      # @return [Chat::Tools::RagQueryGenerator::Result]
      def generate(user_text)
        text = user_text.to_s.strip
        return fallback(text) if text.blank?

        raw = client.chat(
          [
            { role: "system", content: Chat::Prompts::RAG_QUERY },
            { role: "user", content: text }
          ],
          response_format: { "type" => "json_object" }
        )
        build_result(parse_json(raw), fallback_text: text)
      rescue Chat::LlmClient::Error, JSON::ParserError
        fallback(text)
      end

      private

      def client
        @client ||= Chat::ModelRegistry.for(:intent).build_client
      end

      def parse_json(raw)
        text = raw.to_s
        candidate = text[/\{.*\}/m] || text
        JSON.parse(candidate)
      end

      def build_result(data, fallback_text:)
        return fallback(fallback_text) unless data.is_a?(Hash)

        queries = Array(data["queries"]).filter_map { |q| q.to_s.strip.presence }.uniq
        queries = [ fallback_text ] if queries.empty?

        Result.new(
          queries: queries.first(5),
          keywords: Array(data["keywords"]).filter_map { |k| k.to_s.strip.presence },
          requires_recent_info: to_bool(data["requires_recent_info"])
        )
      end

      def to_bool(value)
        return value if value == true || value == false

        %w[true 1 yes].include?(value.to_s.strip.downcase)
      end

      def fallback(text)
        Result.new(queries: [ text ], keywords: [], requires_recent_info: false)
      end
    end
  end
end
