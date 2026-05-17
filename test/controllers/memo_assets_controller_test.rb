# frozen_string_literal: true

require "test_helper"

class MemoAssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(:one)
    @memo = memos(:one)
    @memo.update_columns(slug: "first-memo-#{@memo.id}", file_committed_at: Time.current)
  end

  test "create rejects memo not committed to git" do
    @memo.update_column(:file_committed_at, nil)
    png = Tempfile.new([ "test", ".png" ])
    png.binmode
    png.write("\x89PNG\r\n\x1a\n")
    png.rewind

    post assets_memo_path(@memo),
      params: { file: Rack::Test::UploadedFile.new(png.path, "image/png", true, original_filename: "chart.png") }
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "コミット"
  end

  test "create uploads image and returns json" do
    png = Tempfile.new([ "test", ".png" ])
    png.binmode
    png.write("\x89PNG\r\n\x1a\n")
    png.rewind

    post assets_memo_path(@memo),
      params: { file: Rack::Test::UploadedFile.new(png.path, "image/png", true, original_filename: "chart.png") }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "chart.png", json["filename"]
    assert_equal "image::chart.png[]", json["asciidoc"]
    assert_includes json["url"], "/memos/#{@memo.id}/assets/chart.png"
  end

  test "show serves uploaded image" do
    repo = MemoRepository.new
    repo.write_asset!(@memo, filename: "show.png", io: StringIO.new("PNGDATA"))

    get asset_memo_path(@memo, "show.png")
    assert_response :success
    assert_equal "PNGDATA", response.body
  end

  test "show returns not found for missing file" do
    get asset_memo_path(@memo, "missing.png")
    assert_response :not_found
  end
end
