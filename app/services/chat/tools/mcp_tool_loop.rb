# frozen_string_literal: true

module Chat
  module Tools
    # LLM 計画 → MCP 実行 → （必要なら）再計画の短いループ。
    class McpToolLoop
      MAX_ROUNDS = 2

      def initialize(account: nil, runner: nil, planner: nil, client: nil)
        @account = account
        @runner = runner || NyoyMcpRunner.new(account: account)
        @planner = planner || McpToolPlanner.new(client: client, account: account)
        @client = client || Chat::NyoyMcpConfig.client(account: account)
      end

      # @param user_text [String]
      # @param intent [String]
      # @param candidate_tools [Array<String>] 実行候補の MCP ツール名
      # @return [Chat::Tools::NyoyMcpRunner::Result]
      def call(user_text:, intent:, candidate_tools:)
        empty = NyoyMcpRunner::Result.new(tools_run: [], tools_skipped: [], context_text: "", errors: [])
        return empty unless @runner.configured?

        names = Array(candidate_tools).map(&:to_s).map(&:strip).reject(&:blank?).uniq
        return empty if names.empty?

        catalog = tool_catalog_for(names)
        merged = empty
        prior_context = nil

        MAX_ROUNDS.times do
          plan = @planner.plan(
            user_text: user_text,
            intent: intent,
            tool_catalog: catalog,
            prior_context: prior_context
          )
          remaining = plan.calls.reject do |call|
            merged.tools_run.include?((call[:name] || call["name"]).to_s)
          end
          break if remaining.empty?

          round = @runner.call_planned(calls: remaining, user_text: user_text)
          merged = merge_results(merged, round)
          prior_context = merged.context_text.presence
          break if round.tools_run.empty?
        end

        return merged if merged.tools_run.any? || merged.errors.any?

        @runner.call(mcp_names: names, user_text: user_text)
      end

      private

      def tool_catalog_for(names)
        allowed = names.map(&:to_s)
        @client.list_tools.select { |tool| allowed.include?(tool["name"].to_s) }
      rescue Chat::NyoyMcpClient::Error
        names.map { |name| { "name" => name, "description" => "", "input_schema" => {} } }
      end

      def merge_results(left, right)
        NyoyMcpRunner::Result.new(
          tools_run: left.tools_run + right.tools_run,
          tools_skipped: (left.tools_skipped + right.tools_skipped).uniq,
          context_text: [ left.context_text, right.context_text ].compact_blank.join("\n\n"),
          errors: left.errors + right.errors
        )
      end
    end
  end
end
