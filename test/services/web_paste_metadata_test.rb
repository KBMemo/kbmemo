# frozen_string_literal: true

require "test_helper"

class WebPasteMetadataTest < ActiveSupport::TestCase
  test "extracts metadata from kbmemo comment and blockquote cite" do
    html = <<~HTML
      <!--kbmemo:{"url":"https://example.com/a","title":"Title A"}-->
      <blockquote cite="https://example.com/a"><p>Text</p></blockquote>
    HTML

    metadata = WebPasteMetadata.extract(html)

    assert_equal "https://example.com/a", metadata.url
    assert_equal "Title A", metadata.title
  end

  test "request params override html metadata" do
    html = '<!--kbmemo:{"url":"https://old.test","title":"Old"}--><p>x</p>'
    metadata = WebPasteMetadata.extract(html, url: "https://new.test", title: "New")

    assert_equal "https://new.test", metadata.url
    assert_equal "New", metadata.title
  end
end
