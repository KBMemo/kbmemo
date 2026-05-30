# frozen_string_literal: true

require "test_helper"

class MemoSvgSourceBlocksTest < ActiveSupport::TestCase
  test "find_all extracts svg source blocks in order" do
    body = <<~ADOC
      intro

      [source,svg]
      ----
      <svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>
      ----

      .Caption
      [source, svg]
      ----
      <svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1"/></svg>
      ----
    ADOC

    blocks = MemoSvgSourceBlocks.find_all(body)
    assert_equal 2, blocks.size
    assert_includes blocks[0][:source], "<circle"
    assert_includes blocks[1][:source], "<rect"
    assert_includes blocks[1][:prefix], ".Caption"
  end

  test "replace updates the nth svg source block and strips scripts" do
    body = <<~ADOC
      [source,svg]
      ----
      <svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>
      ----
    ADOC
    updated = <<~SVG.strip
      <svg xmlns="http://www.w3.org/2000/svg">
        <circle r="2"/>
        <script>alert(1)</script>
      </svg>
    SVG

    out = MemoSvgSourceBlocks.replace(body, index: 0, new_source: updated)
    assert_includes out, 'r="2"'
    assert_not_includes out, "script"
    assert_match(/\n  <circle r="2"/, out)
    refute_match(/------/, out)
  end

  test "replace swaps content between opening and closing delimiters with five dashes" do
    body = <<~ADOC
      [source,svg]
      ----
      <svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>
      -----
    ADOC

    out = MemoSvgSourceBlocks.replace(
      body,
      index: 0,
      new_source: '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>'
    )

    assert_includes out, "<rect"
    assert_not_includes out, "<circle"
    assert_match(/-----\s*\z/, out)
    refute_match(/------/, out)
  end

  test "find_all accepts crlf line endings" do
    body = "= title\r\n\r\n[source, svg]\r\n----\r\n<svg xmlns=\"http://www.w3.org/2000/svg\"><circle r=\"1\"/></svg>\r\n----\r\n"
    blocks = MemoSvgSourceBlocks.find_all(body)
    assert_equal 1, blocks.size
    assert_includes blocks[0][:source], "<circle"
  end

  test "fetch raises when index is missing" do
    assert_raises(MemoSvgSourceBlocks::NotFound) do
      MemoSvgSourceBlocks.fetch("no svg here", index: 0)
    end
  end
end
