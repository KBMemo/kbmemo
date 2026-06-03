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

  test "removes github heading permalink anchors and svg icons" do
    html = <<~HTML
      <h2>
        <a id="user-content-wavespeed" class="anchor" href="#wavespeed">
          <svg class="octicon octicon-link" aria-hidden="true"><path d="m7.775 3.275"/></svg>
        </a>
        WaveSpeed
      </h2>
    HTML

    prepared = ClipHtmlPreparer.prepare(html)

    assert_includes prepared, "WaveSpeed"
    assert_not_includes prepared, "<svg"
    assert_not_includes prepared, 'href="#wavespeed"'
  end
end
