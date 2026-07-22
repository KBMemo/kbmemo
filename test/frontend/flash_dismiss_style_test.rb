# frozen_string_literal: true

require "test_helper"

class FlashDismissStyleTest < ActiveSupport::TestCase
  test "dismiss icon has no idle border or background and keeps a focus indicator" do
    source = Rails.root.join("app/frontend/styles/themes.css").read
    rule = source.match(/\.kb-flash-dismiss \{(?<body>.*?)\}/m)&.named_captures&.fetch("body")

    assert_includes rule, "border: 0"
    assert_includes rule, "background: transparent"
    assert_match(/\.kb-flash-dismiss:focus-visible \{.*(?:box-shadow|outline):/m, source)
  end
end
