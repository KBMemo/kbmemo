# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class McpToolLoopTest < ActiveSupport::TestCase
      test "executes planned calls" do
        planned_calls = nil
        runner = Object.new
        runner.define_singleton_method(:configured?) { true }
        runner.define_singleton_method(:call_planned) do |calls:, user_text:|
          planned_calls = calls
          NyoyMcpRunner::Result.new(
            tools_run: [ "fetch_url" ],
            tools_skipped: [],
            context_text: "fetched",
            errors: []
          )
        end
        runner.define_singleton_method(:call) { |**| raise "should not fallback" }

        planner = Object.new
        planner.define_singleton_method(:plan) do |**|
          McpToolPlanner::Plan.new(
            calls: [ { name: "fetch_url", arguments: { url: "https://example.com" } } ],
            reason: "url"
          )
        end

        client = Object.new
        client.define_singleton_method(:list_tools) do
          [ { "name" => "fetch_url", "description" => "", "input_schema" => {} } ]
        end

        result = McpToolLoop.new(runner: runner, planner: planner, client: client).call(
          user_text: "https://example.com を読んで",
          intent: "url_analysis",
          candidate_tools: [ "fetch_url" ]
        )

        assert_equal [ "fetch_url" ], result.tools_run
        assert_equal 1, planned_calls.size
      end

      test "falls back to heuristic runner when planner returns empty" do
        fallback_names = nil
        runner = Object.new
        runner.define_singleton_method(:configured?) { true }
        runner.define_singleton_method(:call_planned) { |**| raise "should not plan" }
        runner.define_singleton_method(:call) do |mcp_names:, user_text:|
          fallback_names = mcp_names
          NyoyMcpRunner::Result.new(
            tools_run: [ "web_search" ],
            tools_skipped: [],
            context_text: "results",
            errors: []
          )
        end

        planner = Object.new
        planner.define_singleton_method(:plan) do |**|
          McpToolPlanner::Plan.new(calls: [], reason: "none")
        end

        client = Object.new
        client.define_singleton_method(:list_tools) { [] }

        result = McpToolLoop.new(runner: runner, planner: planner, client: client).call(
          user_text: "最新情報",
          intent: "web_research",
          candidate_tools: [ "web_search" ]
        )

        assert_equal [ "web_search" ], result.tools_run
        assert_equal [ "web_search" ], fallback_names
      end

      test "runs second planning round with prior context" do
        rounds = []
        runner = Object.new
        runner.define_singleton_method(:configured?) { true }
        runner.define_singleton_method(:call_planned) do |calls:, user_text:|
          rounds << calls.map { |call| call[:name] }
          NyoyMcpRunner::Result.new(
            tools_run: calls.map { |call| call[:name] },
            tools_skipped: [],
            context_text: "### Nyoy MCP: fetch_url\n#{JSON.generate(page_id: "p1", truncated: true)}",
            errors: []
          )
        end
        runner.define_singleton_method(:call) { |**| raise "unexpected fallback" }

        planner = Object.new
        planner.define_singleton_method(:plan) do |prior_context: nil, **|
          if prior_context.blank?
            McpToolPlanner::Plan.new(
              calls: [ { name: "fetch_url", arguments: { url: "https://example.com" } } ],
              reason: "fetch"
            )
          else
            McpToolPlanner::Plan.new(
              calls: [ { name: "search_fetched_page", arguments: { page_id: "p1", query: "価格" } } ],
              reason: "search"
            )
          end
        end

        client = Object.new
        client.define_singleton_method(:list_tools) { [ { "name" => "fetch_url" }, { "name" => "search_fetched_page" } ] }

        result = McpToolLoop.new(runner: runner, planner: planner, client: client).call(
          user_text: "https://example.com の価格は？",
          intent: "url_analysis",
          candidate_tools: %w[fetch_url search_fetched_page]
        )

        assert_equal [ [ "fetch_url" ], [ "search_fetched_page" ] ], rounds
        assert_includes result.tools_run, "search_fetched_page"
      end
    end
  end
end
