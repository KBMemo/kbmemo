# frozen_string_literal: true

require "test_helper"

module Chat
  class ServerModelsTest < ActiveSupport::TestCase
    setup do
      Chat::ServerModels.reset_cache!
      Rails.cache.clear
    end

    test "primary_id returns model id from /v1/models" do
      fake_http = build_fake_http(
        body: { "data" => [ { "id" => "google/gemma-3-4b-it" } ] }.to_json
      )

      Net::HTTP.stub(:new, fake_http) do
        assert_equal "google/gemma-3-4b-it", Chat::ServerModels.primary_id(
          base_url: "http://localhost:10011",
          fallback: "gemma-4-e4b"
        )
      end
    end

    test "primary_id prefers configured model when listed by server" do
      fake_http = build_fake_http(
        body: {
          "data" => [
            { "id" => "google/gemma-3-4b-it" },
            { "id" => "gemma-4-e4b" }
          ]
        }.to_json
      )

      Net::HTTP.stub(:new, fake_http) do
        assert_equal "gemma-4-e4b", Chat::ServerModels.primary_id(
          base_url: "http://localhost:10011",
          fallback: "gemma-4-e4b"
        )
      end
    end

    test "primary_id falls back when server is unreachable" do
      fake_http = Object.new
      def fake_http.use_ssl=(_); end
      def fake_http.open_timeout=(_); end
      def fake_http.read_timeout=(_); end
      def fake_http.request(_) = raise(Errno::ECONNREFUSED)

      Net::HTTP.stub(:new, fake_http) do
        assert_equal "gemma-4-e4b", Chat::ServerModels.primary_id(
          base_url: "http://localhost:9",
          fallback: "gemma-4-e4b"
        )
      end
    end

    private

    def build_fake_http(body:, on_request: nil)
      Object.new.tap do |fake_http|
        fake_http.define_singleton_method(:use_ssl=) { |_| }
        fake_http.define_singleton_method(:open_timeout=) { |_| }
        fake_http.define_singleton_method(:read_timeout=) { |_| }
        fake_http.define_singleton_method(:request) do |_request|
          on_request&.call
          response = Object.new
          response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
          response.define_singleton_method(:body) { body }
          response
        end
      end
    end
  end
end
