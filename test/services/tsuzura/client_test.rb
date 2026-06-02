# frozen_string_literal: true

require "test_helper"

module Tsuzura
  class ClientTest < ActiveSupport::TestCase
    test "list_albums requests internal albums path on Tsuzura host" do
      captured_uri = nil
      response = Object.new
      def response.is_a?(klass)
        klass == Net::HTTPSuccess
      end
      def response.body
        { albums: [] }.to_json
      end

      fake_http = Object.new
      def fake_http.request(_request)
        @response
      end
      fake_http.instance_variable_set(:@response, response)

      with_env(
        "TSUZURA_BASE_URL" => "http://localhost:3008",
        "KBMEMO_TSUZURA_INTERNAL_SECRET" => "test-secret"
      ) do
        Client.stub(:http, lambda { |uri|
          captured_uri = uri
          fake_http
        }) do
          Client.list_albums(owner_account_id: 42)
        end
      end

      assert_equal "/internal/albums", captured_uri.path
      assert_includes captured_uri.query, "owner_account_id=42"
    end

    private

    def with_env(overrides)
      previous = overrides.keys.index_with { |key| ENV[key] }
      overrides.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
