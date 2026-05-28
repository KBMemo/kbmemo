# frozen_string_literal: true

require "test_helper"

class ClipHtmlPreparerTest < ActiveSupport::TestCase
  test "unwraps bookmarklet blockquote before conversion" do
    html = <<~HTML
      <!--kbmemo:{"url":"https://example.com/article","title":"Article"}-->
      <blockquote cite="https://example.com/article"><p><strong>Clip</strong> body</p></blockquote>
    HTML

    prepared = ClipHtmlPreparer.prepare(html)

    assert_not_includes prepared, "<blockquote"
    assert_includes prepared, "<strong>Clip</strong>"
  end

  test "strips presentation attributes from clipped html" do
    html = <<~HTML
      <div class="HeroSection_scheduleItem__CUhfj" id="schedule" style="color:red" data-test="1">
        <span class="HeroSection_scheduleLabel__rVBvI">投稿募集開始</span>
        <span class="HeroSection_scheduleValue__ZbeZQ">2026.05.11</span>
      </div>
    HTML

    prepared = ClipHtmlPreparer.prepare(html)

    assert_includes prepared, "投稿募集開始"
    assert_includes prepared, "2026.05.11"
    assert_not_includes prepared, "class="
    assert_not_includes prepared, "HeroSection_"
    assert_not_includes prepared, 'data-test="1"'
  end
end
