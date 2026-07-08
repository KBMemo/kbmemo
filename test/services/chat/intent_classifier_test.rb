# frozen_string_literal: true

require "test_helper"

module Chat
  class IntentClassifierTest < ActiveSupport::TestCase
    # 固定応答を返すスタブクライアント。
    class StubClient
      def initialize(response)
        @response = response
      end

      def chat(_messages, **_opts)
        raise @response if @response.is_a?(StandardError)

        @response
      end
    end

    def classifier_for(response)
      Chat::IntentClassifier.new(client: StubClient.new(response))
    end

    test "parses well-formed JSON" do
      result = classifier_for(
        '{"intent":"code","confidence":0.9,"needs_tool":false,"reason":"実装相談"}'
      ).classify("この関数を直して")

      assert_equal "code", result.intent
      assert_in_delta 0.9, result.confidence
      assert_equal false, result.needs_tool
      assert_equal "実装相談", result.reason
    end

    test "extracts JSON embedded in code fence and prose" do
      raw = "以下です:\n```json\n{\"intent\":\"web_research\",\"confidence\":0.8,\"needs_tool\":true}\n```"
      result = classifier_for(raw).classify("最新の情報を教えて")

      assert_equal "web_research", result.intent
      assert_equal true, result.needs_tool
    end

    test "unknown intent value falls back to unknown" do
      result = classifier_for('{"intent":"banana","confidence":0.5}').classify("x")
      assert_equal "unknown", result.intent
    end

    test "clamps out-of-range confidence" do
      result = classifier_for('{"intent":"conversation","confidence":5}').classify("hi")
      assert_in_delta 1.0, result.confidence
    end

    test "blank input returns unknown without calling client" do
      result = Chat::IntentClassifier.new(client: StubClient.new("should not be used")).classify("   ")
      assert_equal "unknown", result.intent
      assert_in_delta 0.0, result.confidence
    end

    test "malformed JSON falls back to unknown" do
      result = classifier_for("not json at all").classify("x")
      assert_equal "unknown", result.intent
    end

    test "client error falls back to unknown" do
      result = classifier_for(Chat::LlmClient::Error.new("down")).classify("x")
      assert_equal "unknown", result.intent
    end
  end
end
