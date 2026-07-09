# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class RagQueryGeneratorTest < ActiveSupport::TestCase
      class StubClient
        def initialize(response)
          @response = response
        end

        def chat(_messages, **_opts)
          raise @response if @response.is_a?(StandardError)

          @response
        end
      end

      test "parses JSON queries" do
        raw = '{"queries":["Rails RAG","pgroonga"],"keywords":["Rails"],"requires_recent_info":false}'
        result = RagQueryGenerator.new(client: StubClient.new(raw)).generate("メモを検索")

        assert_equal [ "Rails RAG", "pgroonga" ], result.queries
        assert_equal [ "Rails" ], result.keywords
        assert_equal false, result.requires_recent_info
      end

      test "falls back to user text on error" do
        result = RagQueryGenerator.new(client: StubClient.new(Chat::LlmClient::Error.new("down"))).generate("清水寺")
        assert_equal [ "清水寺" ], result.queries
      end

      test "blank input falls back without calling client" do
        result = RagQueryGenerator.new(client: StubClient.new("should not run")).generate("   ")
        assert_equal [ "" ], result.queries
      end
    end
  end
end
