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

      # ユーザー文だけから引数を組める MCP ツール（UI 有効化時の直接実行も可）。
      DIRECT_MCP_TOOLS = %w[
        web_search
        fetch_url
        generate_image
        analyze_image
        list_prompt_styles
        search_memos
        recall_memos
        list_albums
        get_media
      ].freeze

      CHAIN_ONLY_MCP_TOOLS = %w[
        search_fetched_page
        get_image_generation
      ].freeze

      MANUAL_MCP_TOOLS = %w[
        create_memo
        update_memo
      ].freeze

      ULID_PATTERN = /\b[0-9A-HJKMNP-TV-Z]{26}\b/

      IMAGE_GENERATION_POLL_INTERVAL = 1.0
      IMAGE_GENERATION_MAX_ATTEMPTS = 30
      IMAGE_GENERATION_COMPLETED = %w[completed done succeeded].freeze
      IMAGE_GENERATION_FAILED = %w[failed error cancelled canceled].freeze

      Session = Struct.new(:user_text, :page_id, keyword_init: true)

      Result = Struct.new(:tools_run, :tools_skipped, :context_text, :errors, keyword_init: true)

      def self.directly_invocable?(name)
        DIRECT_MCP_TOOLS.include?(name.to_s)
      end

      def initialize(client: nil, account: nil, poll_sleep: nil)
        @client = client || Chat::NyoyMcpConfig.client(account: account)
        @poll_sleep = poll_sleep || method(:default_poll_sleep)
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

        session = Session.new(user_text: user_text.to_s)
        run = []
        skipped = []
        errors = []
        chunks = []

        names.each do |mcp_name|
          execute_tool(mcp_name, session:, run:, skipped:, errors:, chunks:)
        end

        Result.new(
          tools_run: run,
          tools_skipped: skipped.uniq,
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

      def execute_tool(mcp_name, session:, run:, skipped:, errors:, chunks:)
        arguments = build_arguments(mcp_name, session)
        if arguments.nil?
          skipped << mcp_name
          return
        end

        payload = @client.call_tool(name: mcp_name, arguments: arguments)
        run << mcp_name
        chunks << format_context(mcp_name, payload)
        chain_follow_ups(mcp_name, payload, session:, run:, skipped:, errors:, chunks:)
      rescue Chat::NyoyMcpClient::Error => e
        errors << { tool: mcp_name, message: e.message }
        skipped << mcp_name
      end

      def chain_follow_ups(mcp_name, payload, session:, run:, skipped:, errors:, chunks:)
        case mcp_name
        when "fetch_url"
          chain_search_fetched_page(payload, session:, run:, skipped:, errors:, chunks:)
        when "generate_image"
          chain_image_generation_poll(payload, run:, skipped:, errors:, chunks:)
        end
      end

      def chain_search_fetched_page(payload, session:, run:, skipped:, errors:, chunks:)
        return unless payload.is_a?(Hash)
        return unless payload["truncated"]
        return if payload["page_id"].blank?

        session.page_id = payload["page_id"].to_s
        execute_tool("search_fetched_page", session:, run:, skipped:, errors:, chunks:)
      end

      def chain_image_generation_poll(payload, run:, skipped:, errors:, chunks:)
        return unless payload.is_a?(Hash)

        generation_id = payload["id"] || payload["image_generation_id"]
        return if generation_id.blank?

        run << "get_image_generation"

        IMAGE_GENERATION_MAX_ATTEMPTS.times do |attempt|
          poll_payload = @client.call_tool(
            name: "get_image_generation",
            arguments: { id: generation_id.to_i }
          )
          upsert_poll_chunk(chunks, poll_payload)

          status = image_generation_status(poll_payload)
          return if status.in?(IMAGE_GENERATION_COMPLETED)
          return if status.in?(IMAGE_GENERATION_FAILED)
          break if attempt + 1 >= IMAGE_GENERATION_MAX_ATTEMPTS

          @poll_sleep.call(IMAGE_GENERATION_POLL_INTERVAL)
        end
      rescue Chat::NyoyMcpClient::Error => e
        errors << { tool: "get_image_generation", message: e.message }
        skipped << "get_image_generation"
      end

      def upsert_poll_chunk(chunks, poll_payload)
        formatted = format_context("get_image_generation", poll_payload)
        poll_label = "### Nyoy MCP: get_image_generation"

        if chunks.last&.start_with?(poll_label)
          chunks[-1] = formatted
        else
          chunks << formatted
        end
      end

      def image_generation_status(payload)
        return "" unless payload.is_a?(Hash)

        (payload["status"] || payload["state"]).to_s.downcase
      end

      def default_poll_sleep(seconds)
        sleep(seconds)
      end

      def normalize_mcp_names(mcp_names:, tools:)
        names = Array(mcp_names).map(&:to_s).map(&:strip).reject(&:blank?)
        return names.uniq if names.any?

        Array(tools).filter_map { |tool| TOOL_MAP[tool.to_sym] }.uniq
      end

      def build_arguments(mcp_name, session)
        user_text = session.user_text.to_s.strip

        case mcp_name
        when "web_search", "search_memos", "recall_memos"
          return nil if user_text.blank?

          { q: user_text }
        when "fetch_url"
          url = Chat::Tools::UrlExtractor.first(session.user_text)
          return nil if url.blank?

          { url: url }
        when "search_fetched_page"
          return nil if session.page_id.blank? || user_text.blank?

          { page_id: session.page_id, query: user_text }
        when "generate_image"
          return nil if user_text.blank?

          { japanese_prompt: user_text }
        when "analyze_image"
          return nil if user_text.blank?

          args = { prompt: user_text }
          media_id = first_ulid(session.user_text)
          args[:tsuzura_media_id] = media_id if media_id.present?
          args
        when "get_media"
          media_id = first_ulid(session.user_text)
          return nil if media_id.blank?

          { tsuzura_media_id: media_id }
        when "list_prompt_styles", "list_albums"
          {}
        when *MANUAL_MCP_TOOLS
          nil
        else
          nil
        end
      end

      def first_ulid(text)
        match = text.to_s.match(ULID_PATTERN)
        match&.to_s
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
