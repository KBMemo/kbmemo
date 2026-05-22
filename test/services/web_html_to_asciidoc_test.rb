# frozen_string_literal: true

require "test_helper"

class WebHtmlToAsciidocTest < ActiveSupport::TestCase
  test "converts bookmarklet-shaped html to asciidoc" do
    html = <<~HTML
      <!--kbmemo:{"url":"https://example.com/page","title":"Example"}-->
      <blockquote cite="https://example.com/page"><p><strong>Hello</strong> world</p></blockquote>
    HTML

    adoc = WebHtmlToAsciidoc.convert(html)

    assert_includes adoc, "*Hello* world"
    assert_includes adoc, "____"
  end

  test "strips kbmemo metadata comment before conversion" do
    html = '<!--kbmemo:{"url":"https://x.test"}--><p>Body</p>'
    assert_equal "Body", WebHtmlToAsciidoc.convert(html)
  end

  test "converts list items without frozen string error" do
    html = "<ul><li>First</li><li><strong>Second</strong></li></ul>"

    adoc = WebHtmlToAsciidoc.convert(html)

    assert_includes adoc, "* First"
    assert_includes adoc, "* Second"
  end
end
