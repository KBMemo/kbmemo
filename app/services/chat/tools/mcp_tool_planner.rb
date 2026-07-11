# frozen_string_literal: true

require "json"

module Chat
  module Tools
    # LFM2.5（intent 役割）で Nyoy MCP ツール呼び出しを JSON 計画する。
    class McpToolPlanner
      Plan = Struct.new(:calls, :reason, keyword_init: true)

      MANUAL_TOOLS = NyoyMcpRunner::MANUAL_MCP_TOOLS.freeze
      AUTO_CHAIN_TOOLS = NyoyMcpRunner::CHAIN_ONLY_MCP_TOOLS.freeze

      def initialize(client: nil, account: nil)
        @client = client
        @account = account
      end

      # @param user_text [String]
      # @param intent [String]
      # @param tool_catalog [Array<Hash>] list_tools のエントリ（name / description / input_schema）
      # @param prior_context [String, nil] 前ラウンドの MCP 実行結果
      # @return [Chat::Tools::McpToolPlanner::Plan]
      def plan(user_text:, intent:, tool_catalog:, prior_context: nil, image_attachments: nil)
        catalog = Array(tool_catalog).filter_map do |entry|
          name = entry["name"].to_s.strip
          next if name.blank?

          {
            "name" => name,
            "description" => entry["description"].to_s,
            "input_schema" => entry["input_schema"] || entry["inputSchema"] || {}
          }
        end
        return empty_plan("利用可能ツールがありません。") if catalog.empty?

        text = user_text.to_s.strip
        return empty_plan("入力が空です。") if text.blank?

        allowed = catalog.map { |entry| entry["name"] }
        user_content = build_user_content(
          user_text: text,
          intent: intent.to_s,
          tool_catalog: catalog,
          prior_context: prior_context,
          image_attachments: image_attachments
        )

        raw = intent_client.chat(
          [
            { role: "system", content: Chat::Prompts::MCP_TOOL_PLANNER },
            { role: "user", content: user_content }
          ],
          response_format: { "type" => "json_object" }
        )
        build_plan(parse_json(raw), allowed: allowed, intent: intent.to_s)
      rescue Chat::LlmClient::Error, JSON::ParserError => e
        empty_plan("計画に失敗しました: #{e.message}")
      end

      private

      def intent_client
        @client || Chat::ModelRegistry.for(:intent, account: @account).build_client
      end

      def build_user_content(user_text:, intent:, tool_catalog:, prior_context:, image_attachments: nil)
        parts = [
          "intent: #{intent}",
          "ユーザー入力:",
          user_text,
          "",
          "利用可能ツール（JSON）:",
          JSON.generate(tool_catalog)
        ]
        attachments = AgentChat::ImageAttachments.normalize(image_attachments)
        if attachments.any?
          parts << ""
          parts << "添付画像（JSON）:"
          parts << JSON.generate(AgentChat::ImageAttachments.as_json(attachments))
          parts << "analyze_image を使う場合は tsuzura_media_id または attachment_index（0 始まり）を指定してください。"
        end
        if prior_context.present?
          parts << ""
          parts << "前回のツール実行結果:"
          parts << prior_context.to_s
        end
        parts.join("\n")
      end

      def parse_json(raw)
        text = raw.to_s
        candidate = text[/\{.*\}/m] || text
        JSON.parse(candidate)
      end

      def build_plan(data, allowed:, intent:)
        return empty_plan("JSON が不正です。") unless data.is_a?(Hash)

        calls = Array(data["calls"]).filter_map do |entry|
          next unless entry.is_a?(Hash)

          name = entry["name"].to_s.strip
          next if name.blank?
          next unless allowed.include?(name)
          next if AUTO_CHAIN_TOOLS.include?(name)
          next if MANUAL_TOOLS.include?(name) && !manual_tool_allowed?(name, intent: intent)

          arguments = normalize_arguments(entry["arguments"])
          next if arguments.nil?

          { name: name, arguments: arguments }
        end

        Plan.new(calls: calls, reason: data["reason"].to_s.strip)
      end

      def manual_tool_allowed?(name, intent:)
        intent == "memo_add" && name == "create_memo"
      end

      def normalize_arguments(raw)
        case raw
        when Hash
          raw.each_with_object({}) do |(key, value), hash|
            next if key.blank?

            hash[key.to_s] = value
          end
        when nil
          {}
        else
          nil
        end
      end

      def empty_plan(reason)
        Plan.new(calls: [], reason: reason)
      end
    end
  end
end
