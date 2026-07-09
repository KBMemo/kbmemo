# frozen_string_literal: true

require "test_helper"

module Chat
  class EmbeddingClientTest < ActiveSupport::TestCase
    test "embed parses llama-server array response" do
      client = Chat::EmbeddingClient.new(base_url: "http://localhost:10034")
      response = [ { "embedding" => [ 0.1, 0.2, 0.3 ] } ]
      client.define_singleton_method(:http_post) { |_content| response }

      assert_equal [ 0.1, 0.2, 0.3 ], client.embed("hello", kind: :query)
    end

    test "embed prefixes query and document differently" do
      client = Chat::EmbeddingClient.new(base_url: "http://localhost:10034")
      captured = nil
      client.define_singleton_method(:http_post) { |content| captured = content; [ { "embedding" => [ 1.0 ] } ] }

      client.embed("text", kind: :query)
      assert_equal "query: text", captured

      client.embed("text", kind: :document)
      assert_equal "passage: text", captured
    end

    test "embed raises connection error on network failure" do
      client = Chat::EmbeddingClient.new(base_url: "http://localhost:9")
      fake_http = Object.new
      def fake_http.use_ssl=(_); end
      def fake_http.open_timeout=(_); end
      def fake_http.read_timeout=(_); end
      def fake_http.request(_) = raise(Errno::ECONNREFUSED)

      Net::HTTP.stub(:new, fake_http) do
        assert_raises(Chat::EmbeddingClient::ConnectionError) { client.embed("x") }
      end
    end
  end
end
