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

  test "does not neutralize stem block delimiters" do
    source = <<~ADOC
      .stem title
      [stem]
      ++++
      E=mc^2
      ++++
    ADOC

    restricted = MemoAdocPassthroughRestrictor.restrict(source)

    assert_includes restricted, "[stem]\n++++\nE=mc^2\n++++"
    assert_not_includes restricted, "...."
  end

  test "does not neutralize latexmath block delimiters" do
    source = <<~ADOC
      [latexmath]
      ++++
      \\sqrt{4}
      ++++
    ADOC

    restricted = MemoAdocPassthroughRestrictor.restrict(source)

    assert_includes restricted, "[latexmath]\n++++\n\\sqrt{4}\n++++"
  end

  test "still neutralizes plain block passthrough alongside a stem block" do
    source = <<~ADOC
      [stem]
      ++++
      E=mc^2
      ++++

      ++++
      <script>alert(1)</script>
      ++++
    ADOC

    restricted = MemoAdocPassthroughRestrictor.restrict(source)

    assert_includes restricted, "[stem]\n++++\nE=mc^2\n++++"
    assert_includes restricted, "....\n<script>alert(1)</script>\n...."
  end
end
