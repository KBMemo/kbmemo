# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class NyoyMcpRunnerTest < ActiveSupport::TestCase
      test "runs web_search with user text" do
        client = stub_client(
          "web_search" => { "results" => [{ "title" => "A" }] }
        )
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call(tools: [ :web_search ], user_text: "最新の Ruby")

        assert_equal [ :web_search ], result.tools_run
        assert_empty result.tools_skipped
        assert_includes result.context_text, "web_search"
        assert_includes result.context_text, "A"
      end

      test "skips fetch_url when user text has no url" do
        client = stub_client
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call(tools: [ :fetch_url ], user_text: "要約して")

        assert_empty result.tools_run
        assert_equal [ :fetch_url ], result.tools_skipped
        assert runner.optional_skip?(:fetch_url, user_text: "要約して")
      end

      test "runs fetch_url when url is present" do
        client = stub_client(
          "fetch_url" => { "title" => "Example", "content_preview" => "body" }
        )
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call(
          tools: [ :fetch_url ],
          user_text: "https://example.com/docs を読んで"
        )

        assert_equal [ :fetch_url ], result.tools_run
        assert_includes result.context_text, "Example"
      end

      test "records errors without raising" do
        client = Object.new
        client.define_singleton_method(:configured?) { true }
        client.define_singleton_method(:call_tool) { |**| raise Chat::NyoyMcpClient::ApiError, "down" }

        runner = NyoyMcpRunner.new(client: client)
        result = runner.call(tools: [ :web_search ], user_text: "q")

        assert_empty result.tools_run
        assert_equal [ :web_search ], result.tools_skipped
        assert_equal "down", result.errors.first[:message]
      end

      private

      def stub_client(responses = {})
        client = Object.new
        client.define_singleton_method(:configured?) { true }
        client.define_singleton_method(:call_tool) do |name:, arguments:|
          responses.fetch(name.to_s) { raise "unexpected tool #{name}" }
        end
        client
      end
    end
  end
end
