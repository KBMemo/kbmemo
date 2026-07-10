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
        err = assert_raises(Chat::LlmClient::ConnectionError) do
          client.chat([ { role: "user", content: "hi" } ])
        end
        assert_match(/接続できませんでした/, err.message)
      end
    end

    test "streamable_chunk? keeps newline-only deltas like Nyoy streamable_text?" do
      assert Chat::LlmClient.streamable_chunk?("\n")
      assert Chat::LlmClient.streamable_chunk?("\n\n")
      refute Chat::LlmClient.streamable_chunk?("")
      refute Chat::LlmClient.streamable_chunk?(nil)
      assert "\n".blank?
    end

    test "parse_stream_delta accepts newline-only content" do
      client = Chat::LlmClient.new(base_url: "http://localhost:10010", model: "m")
      delta = client.send(
        :parse_stream_delta,
        { "choices" => [ { "delta" => { "content" => "\n" } } ] }
      )

      assert_equal "\n", delta[:content]
    end

    test "chat_stream preserves newline chunks in accumulated reply" do
      client = Chat::LlmClient.new(base_url: "http://localhost:10010", model: "m")
      events = [
        { "choices" => [ { "delta" => { "content" => "得られました。" } } ] },
        { "choices" => [ { "delta" => { "content" => "\n\n" } } ] },
        { "choices" => [ { "delta" => { "content" => "---\n\n" } } ] },
        { "choices" => [ { "delta" => { "content" => "### 見出し\n\n" } } ] },
        { "choices" => [ { "delta" => { "content" => "本文" } } ] }
      ]
      sse = events.map { |event| "data: #{JSON.generate(event)}\n\n" }.join + "data: [DONE]\n\n"

      fake_response = Object.new
      def fake_response.is_a?(klass) = klass == Net::HTTPSuccess
      def fake_response.read_body
        yield @body
      end
      fake_response.instance_variable_set(:@body, sse)

      fake_http = Object.new
      def fake_http.use_ssl=(_); end
      def fake_http.open_timeout=(_); end
      def fake_http.read_timeout=(_); end
      def fake_http.request(_)
        if block_given?
          yield @response
        else
          @response
        end
      end
      fake_http.instance_variable_set(:@response, fake_response)

      Net::HTTP.stub(:new, fake_http) do
        reply = client.chat([ { role: "user", content: "hi" } ], stream: true)
        assert_includes reply, "得られました。"
        assert_includes reply, "---"
        assert_includes reply, "### 見出し"
        assert_includes reply, "本文"
        assert_match(/得られました。\n\n---\n\n### 見出し\n\n本文\z/m, reply)
      end
    end
  end
end

