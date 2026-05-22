# frozen_string_literal: true

require "test_helper"

class PandocHtmlToAsciidocTest < ActiveSupport::TestCase
  setup do
    skip "pandoc が必要です" unless pandoc_available?
  end

  test "converts bookmarklet-shaped html to asciidoc" do
    html = <<~HTML
      <!--kbmemo:{"url":"https://example.com/page","title":"Example"}-->
      <blockquote cite="https://example.com/page"><p><strong>Hello</strong> world</p></blockquote>
    HTML

    adoc = PandocHtmlToAsciidoc.convert(html)

    assert_includes adoc, "*Hello*"
  end

  test "strips kbmemo metadata comment before conversion" do
    html = '<!--kbmemo:{"url":"https://x.test"}--><p>Body</p>'
    assert_equal "Body", PandocHtmlToAsciidoc.convert(html)
  end

  test "converts list items" do
    html = "<ul><li>First</li><li><strong>Second</strong></li></ul>"
    adoc = PandocHtmlToAsciidoc.convert(html)

    assert_includes adoc, "* First"
    assert_includes adoc, "*Second*"
  end

  private

  def pandoc_available?
    PandocRunner.pandoc_path.present?
  end
end
