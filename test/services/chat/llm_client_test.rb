# frozen_string_literal: true

require "test_helper"

module Chat
  class LlmClientTest < ActiveSupport::TestCase
    test "chat returns assistant content on success" do
      response_body = {
        "choices" => [
          { "message" => { "role" => "assistant", "content" => "== Title\n\nBody" } }
        ]
      }

      client = Chat::LlmClient.new(base_url: "http://localhost:10010", model: "gemma-4-12b")
      captured = nil
      client.define_singleton_method(:http_post) do |payload|
        captured = payload
        response_body
      end

      assert_equal "== Title\n\nBody", client.chat([ { role: "user", content: "hi" } ], temperature: 0.5)
      assert_equal "gemma-4-12b", captured[:model]
      assert_equal 0.5, captured[:temperature]
    end

    test "chat forwards response_format for JSON tasks" do
      client = Chat::LlmClient.new(base_url: "http://localhost:10031", model: "lfm2.5-1.2b")
      captured = nil
      client.define_singleton_method(:http_post) do |payload|
        captured = payload
        { "choices" => [ { "message" => { "content" => "{}" } } ] }
      end

      client.chat([ { role: "user", content: "x" } ], response_format: { "type" => "json_object" })
      assert_equal({ "type" => "json_object" }, captured[:response_format])
    end

    test "chat raises when base_url blank" do
      client = Chat::LlmClient.new(base_url: "", model: "m")
      assert_raises(Chat::LlmClient::Error) { client.chat([ { role: "user", content: "hi" } ]) }
    end

    test "endpoint normalizes trailing slash and /v1 suffix" do
      client = Chat::LlmClient.new(base_url: "http://localhost:10010/v1/", model: "m")
      assert_equal "http://localhost:10010/v1/chat/completions", client.send(:endpoint).to_s
    end

    test "wraps network errors in Error" do
      client = Chat::LlmClient.new(base_url: "http://localhost:9", model: "m")
      fake_http = Object.new
      def fake_http.use_ssl=(_); end
      def fake_http.open_timeout=(_); end
      def fake_http.read_timeout=(_); end
      def fake_http.request(_) = raise(Errno::ECONNREFUSED)

      Net::HTTP.stub(:new, fake_http) do
        err = assert_raises(Chat::LlmClient::Error) do
          client.chat([ { role: "user", content: "hi" } ])
        end
        assert_match(/接続できませんでした/, err.message)
      end
    end
  end
end
