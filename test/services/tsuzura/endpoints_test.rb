# frozen_string_literal: true

require "test_helper"

module Tsuzura
  class EndpointsTest < ActiveSupport::TestCase
    test "test env defaults to localhost when env is unset" do
      with_env("TSUZURA_PUBLIC_URL" => nil, "TSUZURA_BASE_URL" => nil) do
        assert_equal "http://localhost:3008", Endpoints.public_url
        assert_equal "http://localhost:3008/", Endpoints.api_base_url
      end
    end

    test "TSUZURA_PUBLIC_URL overrides default" do
      with_env("TSUZURA_PUBLIC_URL" => "https://media.kbmemo.net") do
        assert_equal "https://media.kbmemo.net", Endpoints.public_url
      end
    end

    private

    def with_env(overrides)
      previous = overrides.keys.index_with { |key| ENV[key] }
      overrides.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
