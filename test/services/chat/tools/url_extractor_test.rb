# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class UrlExtractorTest < ActiveSupport::TestCase
      test "extracts first http url" do
        url = UrlExtractor.first("このページ https://example.com/foo を見て")
        assert_equal "https://example.com/foo", url
      end

      test "returns nil when no url" do
        assert_nil UrlExtractor.first("URL なし")
      end
    end
  end
end
