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

  test "keeps style rules needed for diagram fills" do
    raw = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg">
        <style>#container .node rect{fill:#ECECFF;stroke:#9370DB;}</style>
        <g class="node"><rect width="50" height="30"/></g>
      </svg>
    SVG

    out = MemoSvgSanitizer.sanitize!(raw)
    assert_includes out, "<style>"
    assert_includes out, "fill:#ECECFF"
    assert_includes out, "<rect"
  end

  test "keeps sanitized foreignObject labels for mermaid" do
    raw = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg">
        <foreignObject width="40" height="24">
          <div xmlns="http://www.w3.org/1999/xhtml">
            <span class="nodeLabel"><p>Start</p></span>
          </div>
        </foreignObject>
      </svg>
    SVG

    out = MemoSvgSanitizer.sanitize!(raw)
    assert_includes out, "<foreignObject"
    assert_includes out, ">Start<"
    assert_not_includes out, "<script"
  end

  test "sanitizes mermaid svg with japanese labels from binary http body" do
    raw = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg">
        <foreignObject width="80" height="24">
          <div xmlns="http://www.w3.org/1999/xhtml">
            <span class="nodeLabel"><p>開始ノード</p></span>
          </div>
        </foreignObject>
      </svg>
    SVG

    out = MemoSvgSanitizer.sanitize!(raw.b)
    assert_match(/開始ノード|&#x958B;&#x59CB;&#x30CE;&#x30FC;&#x30C9;/, out)
    assert_equal Encoding::UTF_8, out.encoding
  end

  test "strips dangerous css in style element" do
    raw = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg">
        <style>rect { fill: red; background: url(javascript:alert(1)); }</style>
        <rect width="10" height="10"/>
      </svg>
    SVG

    out = MemoSvgSanitizer.sanitize!(raw)
    assert_not_includes out, "javascript:"
    assert_includes out, "fill: red"
  end
end
