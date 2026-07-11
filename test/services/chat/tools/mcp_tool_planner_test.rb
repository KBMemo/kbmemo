# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class McpToolPlannerTest < ActiveSupport::TestCase
      test "builds plan from llm json" do
        client = stub_client(
          calls: [
            { "name" => "web_search", "arguments" => { "q" => "llama.cpp 最新" } }
          ],
          reason: "最新情報"
        )
        planner = McpToolPlanner.new(client: client)

        plan = planner.plan(
          user_text: "llama.cpp の最新版は？",
          intent: "web_research",
          tool_catalog: [
            {
              "name" => "web_search",
              "description" => "Web search",
              "input_schema" => { "required" => [ "q" ] }
            }
          ]
        )

        assert_equal 1, plan.calls.size
        assert_equal "web_search", plan.calls.first[:name]
        assert_equal "llama.cpp 最新", plan.calls.first[:arguments]["q"]
      end

      test "filters tools outside catalog" do
        client = stub_client(
          calls: [
            { "name" => "web_search", "arguments" => { "q" => "a" } },
            { "name" => "unknown_tool", "arguments" => {} }
          ]
        )
        planner = McpToolPlanner.new(client: client)

        plan = planner.plan(
          user_text: "調べて",
          intent: "web_research",
          tool_catalog: [ { "name" => "web_search", "description" => "", "input_schema" => {} } ]
        )

        assert_equal [ "web_search" ], plan.calls.map { |call| call[:name] }
      end

      test "blocks create_memo unless memo_add intent" do
        client = stub_client(
          calls: [ { "name" => "create_memo", "arguments" => { "title" => "T", "body" => "B" } } ]
        )
        planner = McpToolPlanner.new(client: client)
        catalog = [ { "name" => "create_memo", "description" => "", "input_schema" => {} } ]

        blocked = planner.plan(user_text: "メモして", intent: "conversation", tool_catalog: catalog)
        allowed = planner.plan(user_text: "メモを保存", intent: "memo_add", tool_catalog: catalog)

        assert_empty blocked.calls
        assert_equal "create_memo", allowed.calls.first[:name]
      end

      private

      def stub_client(payload)
        client = Object.new
        client.define_singleton_method(:chat) do |_messages, **_opts|
          JSON.generate(payload)
        end
        client
      end
    end
  end
end
