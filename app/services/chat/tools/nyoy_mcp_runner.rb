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

      MCP_TO_SYMBOL = TOOL_MAP.invert.freeze

      Result = Struct.new(:tools_run, :tools_skipped, :context_text, :errors, keyword_init: true)

      def initialize(client: nil, account: nil)
        @client = client || Chat::NyoyMcpConfig.client(account: account)
      end

      def configured?
        @client.configured?
      end

      # @param tools [Array<Symbol>] Router 由来のシンボル（後方互換）
      # @param mcp_names [Array<String>] Nyoy MCP のツール名
      # @param user_text [String]
      def call(tools: nil, mcp_names: nil, user_text:)
        empty = Result.new(tools_run: [], tools_skipped: [], context_text: "", errors: [])
        return empty unless configured?

        names = normalize_mcp_names(mcp_names: mcp_names, tools: tools)
        return empty if names.empty?

        run = []
        skipped = []
        errors = []
        chunks = []

        names.each do |mcp_name|
          arguments = build_arguments(mcp_name, user_text)
          if arguments.nil?
            skipped << mcp_name
            next
          end

          payload = @client.call_tool(name: mcp_name, arguments: arguments)
          run << mcp_name
          chunks << format_context(mcp_name, payload)
        rescue Chat::NyoyMcpClient::Error => e
          errors << { tool: mcp_name, message: e.message }
          skipped << mcp_name
        end

        Result.new(
          tools_run: run,
          tools_skipped: skipped,
          context_text: chunks.compact.join("\n\n"),
          errors: errors
        )
      end

      def optional_skip?(tool, user_text:)
        mcp_name = TOOL_MAP[tool]
        return false unless mcp_name

        mcp_name == "fetch_url" && Chat::Tools::UrlExtractor.first(user_text).blank?
      end

      private

      def normalize_mcp_names(mcp_names:, tools:)
        names = Array(mcp_names).map(&:to_s).map(&:strip).reject(&:blank?)
        return names.uniq if names.any?

        Array(tools).filter_map { |tool| TOOL_MAP[tool.to_sym] }.uniq
      end

      def build_arguments(mcp_name, user_text)
        case mcp_name
        when "web_search"
          query = user_text.to_s.strip
          return nil if query.blank?

          { q: query }
        when "fetch_url"
          url = Chat::Tools::UrlExtractor.first(user_text)
          return nil if url.blank?

          { url: url }
        when "generate_image"
          prompt = user_text.to_s.strip
          return nil if prompt.blank?

          { japanese_prompt: prompt }
        when "analyze_image"
          prompt = user_text.to_s.strip
          return nil if prompt.blank?

          { prompt: prompt }
        when "list_prompt_styles"
          {}
        when "create_memo", "update_memo"
          nil
        else
          nil
        end
      end

      def format_context(mcp_name, payload)
        body =
          if payload.is_a?(Hash)
            JSON.pretty_generate(payload)
          else
            payload.to_s
          end

        symbol = MCP_TO_SYMBOL[mcp_name]
        label = symbol ? "#{mcp_name} (#{symbol})" : mcp_name
        "### Nyoy MCP: #{label}\n#{body}"
      end
    end
  end
end
