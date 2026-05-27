# frozen_string_literal: true

require "test_helper"

class ClipImageSrcTest < ActiveSupport::TestCase
  test "unwraps qiita imgix url to s3 origin" do
    imgix = "https://qiita-user-contents.imgix.net/https%3A%2F%2Fqiita-image-store.s3.amazonaws.com%2F0%2F202772%2Fpic.png?ixlib=rb-4.0.0"
    s3 = "https://qiita-image-store.s3.amazonaws.com/0/202772/pic.png"

    assert_equal s3, ClipImageSrc.unwrap_imgix_proxy(imgix)
  end

  test "prefers data-src over placeholder src" do
    html = <<~HTML
      <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
           data-src="https://example.com/photo.png" alt="photo.png">
    HTML
    img = Nokogiri::HTML.fragment(html).at_css("img")

    assert_equal "https://example.com/photo.png", ClipImageSrc.effective_src(img)
  end

  test "filename hint prefers alt with extension" do
    html = '<img src="https://example.com/x" alt="3d.png">'
    img = Nokogiri::HTML.fragment(html).at_css("img")

    assert_equal "3d.png", ClipImageSrc.filename_hint(img, "https://example.com/x")
  end
end
