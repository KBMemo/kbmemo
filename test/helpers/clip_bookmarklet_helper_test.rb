# frozen_string_literal: true

require "test_helper"

class ClipBookmarkletHelperTest < ActiveSupport::TestCase
  test "api_bookmarklet_href embeds base origin and token" do
    href = ClipBookmarkletHelper.api_bookmarklet_href(
      "https://kbmemo.example.com/profile/edit",
      "kbmemo_test_token_abc"
    )

    assert href.start_with?("javascript:")
    decoded = URI.decode_www_form_component(href.delete_prefix("javascript:"))
    assert_includes decoded, "https://kbmemo.example.com"
    assert_includes decoded, "kbmemo_test_token_abc"
    assert_not_includes decoded, "__KBMEMO_BASE__"
    assert_not_includes decoded, "__KBMEMO_TOKEN__"
  end

  test "clipboard_bookmarklet_href is javascript url" do
    href = ClipBookmarkletHelper.clipboard_bookmarklet_href

    assert href.start_with?("javascript:")
    assert_includes URI.decode_www_form_component(href.delete_prefix("javascript:")), "clipboard.write"
  end
end
