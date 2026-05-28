# frozen_string_literal: true

require "test_helper"

class MemoAdocPassthroughRestrictorTest < ActiveSupport::TestCase
  test "converts block passthrough delimiters to literal blocks" do
    source = <<~ADOC
      ++++
      <script>alert(1)</script>
      ++++
    ADOC

    restricted = MemoAdocPassthroughRestrictor.restrict(source)

    assert_includes restricted, "....\n<script>alert(1)</script>\n...."
    assert_not_includes restricted, "++++"
  end

  test "closes unterminated block passthrough as literal" do
    source = <<~ADOC
      ++++
      <script>alert(1)</script>
    ADOC

    restricted = MemoAdocPassthroughRestrictor.restrict(source)

    assert restricted.start_with?("....\n<script>alert(1)</script>")
    assert restricted.end_with?("....")
  end

  test "escapes inline pass macro passthrough" do
    source = "pass:[<script>alert(1)</script>]"

    assert_equal '\pass:[<script>alert(1)</script>]', MemoAdocPassthroughRestrictor.restrict(source)
  end

  test "escapes inline triple-plus passthrough" do
    source = "+++<del>removed</del>+++"

    assert_equal '\+++<del>removed</del>+++', MemoAdocPassthroughRestrictor.restrict(source)
  end
end
