# frozen_string_literal: true

require "test_helper"

class ClipImageImporterTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @repo = MemoRepository.new
  end

  test "downloads remote image and rewrites src to memo asset url" do
    png = "\x89PNG\r\n\x1a\nFAKE"
    importer = ClipImageImporter.new(@memo, base_url: "https://example.com/article", repo: @repo)

    importer.define_singleton_method(:fetch) do |url, redirect_limit: 3|
      [ png, "image/png", "photo.png" ]
    end

    html = '<p><img src="https://example.com/photo.png" alt="pic"></p>'
    result = importer.localize!(html)

    assert_includes result, MemoAssets.asset_url_for(@memo, "photo.png")
    assert @repo.absolute_asset_path_for(@memo, "photo.png").exist?
  end

  test "skips already localized asset urls" do
    importer = ClipImageImporter.new(@memo, repo: @repo)
    asset_url = MemoAssets.asset_url_for(@memo, "existing.png")
    html = %(<p><img src="#{asset_url}" alt="pic"></p>)

    importer.define_singleton_method(:fetch) do |*|
      raise "should not fetch"
    end

    assert_equal html, importer.localize!(html)
  end

  test "imports qiita imgix linked image with alt filename and clean asciidoc" do
    html = <<~HTML
      <p><a href="https://qiita-image-store.s3.amazonaws.com/0/202772/08cb9354-713e-17e8-d64e-915dbc6b41f5.png" target="_blank" rel="noopener noreferrer"><img src="https://qiita-user-contents.imgix.net/https%3A%2F%2Fqiita-image-store.s3.amazonaws.com%2F0%2F202772%2F08cb9354-713e-17e8-d64e-915dbc6b41f5.png?ixlib=rb-4.0.0&amp;auto=format&amp;gif-q=60&amp;q=75&amp;s=82089edc1f8c52fa9ad2b050025588af" alt="3d.png"></a></p>
    HTML
    png = "\x89PNG\r\n\x1a\nFAKE"
    importer = ClipImageImporter.new(@memo, base_url: "https://qiita.com/items/x", repo: @repo)
    fetched_urls = []
    importer.define_singleton_method(:fetch) do |url, redirect_limit: 3|
      fetched_urls << url
      [ png, "image/png", "08cb9354-713e-17e8-d64e-915dbc6b41f5.png" ]
    end

    localized = importer.localize!(html, src_format: :filename)
    adoc = PandocHtmlToAsciidoc.convert(localized)

    assert_includes fetched_urls.first, "qiita-image-store.s3.amazonaws.com"
    assert_includes localized, 'src="3d.png"'
    assert_not_includes localized, "<a "
    assert_includes localized, "image::3d.png"
    assert_includes localized, "link=https://qiita-image-store.s3.amazonaws.com"
    assert_includes adoc, "3d.png"
    assert_includes adoc, "link=https://qiita-image-store.s3.amazonaws.com"
    assert_not_includes adoc, "qiita-user-contents.imgix.net"
    assert_not_includes adoc, "https%3A"
    assert @repo.absolute_asset_path_for(@memo, "3d.png").exist?
  end

  test "marks up github-style linked badge for pandoc" do
    html = <<~HTML
      <p><a href="https://github.com/WaveSpeedAI/wavespeed-desktop/releases/latest"><img src="https://camo.githubusercontent.com/badge.png" alt="GitHub Release"></a></p>
    HTML
    png = "\x89PNG\r\n\x1a\nFAKE"
    importer = ClipImageImporter.new(@memo, base_url: "https://github.com/WaveSpeedAI/wavespeed-desktop", repo: @repo)
    importer.define_singleton_method(:fetch) do |_url, redirect_limit: 3|
      [ png, "image/png", "badge.png" ]
    end

    localized = importer.localize!(html, src_format: :filename)

    assert_includes localized, "image::badge.png[GitHub Release, link=https://github.com/WaveSpeedAI/wavespeed-desktop/releases/latest]"
    assert_not_includes localized, "<a "
    assert_not_includes localized, "camo.githubusercontent.com"
    assert @repo.absolute_asset_path_for(@memo, "badge.png").exist?
  end

  test "imports lazy-loaded image from data-src" do
    html = <<~HTML
      <p><img data-src="https://qiita-user-contents.imgix.net/https%3A%2F%2Fqiita-image-store.s3.amazonaws.com%2F0%2F202772%2Fpic.png?ixlib=rb-4.0.0"
           src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
           alt="pic.png"></p>
    HTML
    importer = ClipImageImporter.new(@memo, base_url: "https://qiita.com/items/x", repo: @repo)
    importer.define_singleton_method(:fetch) do |url, redirect_limit: 3|
      [ "\x89PNG\r\n\x1a\n", "image/png", "pic.png" ]
    end

    localized = importer.localize!(html, src_format: :filename)

    assert_includes localized, 'src="pic.png"'
    assert_not_includes localized, "data-src"
  end
end
