# frozen_string_literal: true

require "test_helper"

class BookmarkletRelayTest < ActiveSupport::TestCase
  test "closes relay popup after opening the saved memo" do
    source = Rails.root.join("public/bookmarklets/relay.html").read

    assert_includes source, "openLink.target = '_blank'"
    assert_includes source, "openLink.addEventListener('click'"
    assert_includes source, "window.setTimeout(() => window.close(), 0)"
  end

  test "forwards clip mode and shows summary progress" do
    source = Rails.root.join("public/bookmarklets/relay.html").read

    assert_includes source, "mode: event.data.mode"
    assert_includes source, "サマリーを生成中"
  end
end
