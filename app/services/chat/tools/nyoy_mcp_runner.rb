# frozen_string_literal: true

module Chat
  module Tools
    # Router が返す未実装ツールを Nyoy MCP tools/call へ委譲する。
    class NyoyMcpRunner
      TOOL_MAP = {
        fetch_url: "fetch_url",
        web_search: "web_search",
        image_analysis: "analyze_image",
        image_generation: "generate_image",
        memo_add: "create_memo"
      }.freeze

      Result = Struct.new(:tools_run, :tools_skipped, :context_text, :errors, keyword_init: true)

      def initialize(client: nil)
        @client = client || Chat::NyoyMcpClient.new
      end

      def configured?
        @client.configured?
      end

      # @param tools [Array<Symbol>]
      # @param user_text [String]
      def call(tools:, user_text:)
        empty = Result.new(tools_run: [], tools_skipped: [], context_text: "", errors: [])
        return empty unless configured?

        run = []
        skipped = []
        errors = []
        chunks = []

        Array(tools).each do |tool|
          mcp_name = TOOL_MAP[tool]
          next unless mcp_name

          arguments = build_arguments(tool, user_text)
          if arguments.nil?
            skipped << tool
            next
          end

          payload = @client.call_tool(name: mcp_name, arguments: arguments)
          run << tool
          chunks << format_context(tool, mcp_name, payload)
        rescue Chat::NyoyMcpClient::Error => e
          errors << { tool: tool.to_s, message: e.message }
          skipped << tool
        end

        Result.new(
          tools_run: run,
          tools_skipped: skipped,
          context_text: chunks.compact.join("\n\n"),
          errors: errors
        )
      end

      def optional_skip?(tool, user_text:)
        tool == :fetch_url && Chat::Tools::UrlExtractor.first(user_text).blank?
      end

      private

      def build_arguments(tool, user_text)
        case tool
        when :web_search
          { q: user_text.to_s.strip }
        when :fetch_url
          url = Chat::Tools::UrlExtractor.first(user_text)
          return nil if url.blank?

          { url: url }
        when :image_generation
          prompt = user_text.to_s.strip
          return nil if prompt.blank?

          { japanese_prompt: prompt }
        when :image_analysis, :memo_add
          nil
        else
          nil
        end
      end

      def format_context(tool, mcp_name, payload)
        body =
          if payload.is_a?(Hash)
            JSON.pretty_generate(payload)
          else
            payload.to_s
          end

        "### Nyoy MCP: #{mcp_name} (#{tool})\n#{body}"
      end
    end
  end
end
