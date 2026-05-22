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
end
