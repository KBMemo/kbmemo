# frozen_string_literal: true

require "test_helper"

class MemoSvgSanitizerTest < ActiveSupport::TestCase
  test "removes script and event handlers" do
    raw = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg">
        <script>alert(1)</script>
        <rect width="10" height="10" onclick="alert(1)"/>
      </svg>
    SVG

    out = MemoSvgSanitizer.sanitize!(raw)
    assert_not_includes out, "<script"
    assert_not_includes out, "onclick"
    assert_includes out, "<rect"
  end

  test "rejects non-svg root" do
    assert_raises(MemoAssets::InvalidFile) do
      MemoSvgSanitizer.sanitize!("<html></html>")
    end
  end
end
