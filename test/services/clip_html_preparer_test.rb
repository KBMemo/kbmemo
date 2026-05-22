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
end
