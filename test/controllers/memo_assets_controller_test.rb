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

  test "show sets csp headers for svg" do
    repo = MemoRepository.new
    repo.write_asset!(@memo, filename: "icon.svg", io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"></svg>'))

    get asset_memo_path(@memo, "icon.svg")
    assert_response :success
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.headers["Content-Security-Policy"], "script-src 'none'"
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

  test "view shows image viewer" do
    repo = MemoRepository.new
    repo.write_asset!(@memo, filename: "viewer.png", io: StringIO.new("PNGDATA"))

    get asset_view_memo_path(@memo, "viewer.png")
    assert_response :success
    assert_includes response.body, 'data-controller="diagram-svg-viewer"'
    assert_includes response.body, "/memos/#{@memo.id}/assets/viewer.png"
    assert_includes response.body, "画面に合わせる"
    assert_includes response.body, "diagram-svg-viewer#zoomIn"
  end

  test "view returns not found for missing file" do
    get asset_view_memo_path(@memo, "missing.png")
    assert_response :not_found
  end

  test "destroy removes asset file" do
    repo = MemoRepository.new
    repo.write_asset!(@memo, filename: "remove-me.png", io: StringIO.new("PNG"))

    delete destroy_asset_memo_path(@memo, asset_path: "remove-me.png")
    assert_response :no_content
    assert_not repo.absolute_asset_path_for(@memo, "remove-me.png").file?
  end

  test "destroy with json accept removes asset file" do
    repo = MemoRepository.new
    repo.write_asset!(@memo, filename: "json-remove.png", io: StringIO.new("PNG"))

    delete destroy_asset_memo_path(@memo, asset_path: "json-remove.png"),
      headers: { "Accept" => "application/json" }

    assert_response :no_content
    assert_not repo.absolute_asset_path_for(@memo, "json-remove.png").file?
  end

  test "destroy removes root svg image via json body" do
    repo = MemoRepository.new
    svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
    repo.write_asset!(@memo, filename: "icon.svg", io: StringIO.new(svg))

    delete "/memos/#{@memo.id}/assets",
      params: { asset_path: "icon.svg" },
      as: :json

    assert_response :no_content
    assert_not repo.absolute_asset_path_for(@memo, "icon.svg").file?
  end

  test "destroy svg keeps brackets in filename" do
    repo = MemoRepository.new
    repo.write_asset!(@memo, filename: "diagrams/[flow].svg", io: StringIO.new("<svg></svg>"))

    delete "/memos/#{@memo.id}/assets",
      params: { asset_path: "diagrams/[flow].svg" },
      as: :json

    assert_response :no_content
    assert_not repo.absolute_asset_path_for(@memo, "diagrams/[flow].svg").file?
  end

  test "destroy svg via legacy filename param split as format" do
    repo = MemoRepository.new
    svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
    repo.write_asset!(@memo, filename: "legacy.svg", io: StringIO.new(svg))

    delete "/memos/#{@memo.id}/assets?filename=legacy&format=svg",
      headers: { "Accept" => "application/json" }

    assert_response :no_content
    assert_not repo.absolute_asset_path_for(@memo, "legacy.svg").file?
  end

  test "destroy removes orphan diagram svg" do
    repo = MemoRepository.new
    repo.write_asset!(@memo, filename: "diagrams/orphan.svg", io: StringIO.new("<svg></svg>"))

    delete destroy_asset_memo_path(@memo, asset_path: "diagrams/orphan.svg"),
      headers: { "Accept" => "application/json" }

    assert_response :no_content
    assert_not repo.absolute_asset_path_for(@memo, "diagrams/orphan.svg").file?
  end

  test "destroy removes jpeg image" do
    repo = MemoRepository.new
    repo.write_asset!(@memo, filename: "photo.jpeg", io: StringIO.new("JPEG"))

    delete destroy_asset_memo_path(@memo, asset_path: "photo.jpeg"),
      headers: { "Accept" => "application/json" }

    assert_response :no_content
    assert_not repo.absolute_asset_path_for(@memo, "photo.jpeg").file?
  end

  test "destroy removes unreferenced diagram source and svg" do
    repo = MemoRepository.new
    repo.write_asset!(@memo, filename: "diagrams/orphan.mmd", io: StringIO.new("graph TD"))
    repo.write_asset!(@memo, filename: "diagrams/orphan.svg", io: StringIO.new("<svg></svg>"))

    delete destroy_asset_memo_path(@memo, asset_path: "diagrams/orphan.mmd"),
      headers: { "Accept" => "application/json" }

    assert_response :no_content
    assert_not repo.absolute_asset_path_for(@memo, "diagrams/orphan.mmd").file?
    assert_not repo.absolute_asset_path_for(@memo, "diagrams/orphan.svg").file?
  end

  test "destroy removes git tracked asset" do
    repo = MemoRepository.new
    repo.write_asset!(@memo, filename: "tracked.png", io: StringIO.new("PNG"))
    repo.write_and_commit!(@memo)
    tracked_rel = repo.assets_dir_relative_for(@memo).join("tracked.png").to_s

    delete destroy_asset_memo_path(@memo, asset_path: "tracked.png"),
      headers: { "Accept" => "application/json" }

    assert_response :no_content
    assert_not repo.absolute_asset_path_for(@memo, "tracked.png").file?

    _out, err, st = Open3.capture3(
      "git", "ls-files", "--error-unmatch", "--", tracked_rel, chdir: repo.root.to_s
    )
    assert_not st.success?, err
  end

  test "show serves diagram svg under diagrams subdirectory" do
    repo = MemoRepository.new
    svg = '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>'
    repo.write_asset!(@memo, filename: "diagrams/flow2.svg", io: StringIO.new(svg))

    get asset_memo_path(@memo, "diagrams/flow2.svg")
    assert_response :success
    assert_includes response.body, "<svg"
  end
end
