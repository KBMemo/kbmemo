# frozen_string_literal: true

require "test_helper"

module Tsuzura
  class MediaUrlSignerTest < ActiveSupport::TestCase
    test "base_url delegates to Endpoints" do
      with_env("TSUZURA_PUBLIC_URL" => nil) do
        assert_equal Endpoints.public_url, MediaUrlSigner.base_url
      end
    end

    test "sign builds url on configured public host" do
      with_env("TSUZURA_PUBLIC_URL" => "http://localhost:3008") do
        url = MediaUrlSigner.sign(media_id: ULID.generate, memo_id: 1)
        assert_includes url, "http://localhost:3008/v1/media/"
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
