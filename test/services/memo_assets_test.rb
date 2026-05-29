# frozen_string_literal: true

require "test_helper"

class MemoAssetsTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @memo.update_columns(slug: memo_global_slug("first-memo", @memo), file_committed_at: Time.current)
    @repo = MemoRepository.new
  end

  test "upload rejects memo not committed to git" do
    @memo.update_column(:file_committed_at, nil)
    file = uploaded_file("diagram.png", "image/png", "PNG")
    error = assert_raises(MemoAssets::InvalidFile) do
      MemoAssets.upload(@memo, file: file, repo: @repo)
    end
    assert_includes error.message, "コミット"
  end

  test "upload writes file under assets dir and returns asciidoc" do
    file = uploaded_file("diagram.png", "image/png", "PNG")
    result = MemoAssets.upload(@memo, file: file, repo: @repo)

    assert_equal "diagram.png", result[:filename]
    assert_equal "image::diagram.png[]", result[:asciidoc]
    assert_includes result[:url], "/memos/#{@memo.id}/assets/diagram.png"

    path = @repo.absolute_asset_path_for(@memo, "diagram.png")
    assert path.file?
    assert_equal "PNG", path.read
  end

  test "upload sanitizes svg and stores without script" do
    raw = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg">
        <script>alert(1)</script>
        <circle cx="5" cy="5" r="4"/>
      </svg>
    SVG
    file = uploaded_file("diagram.svg", "image/svg+xml", raw)
    result = MemoAssets.upload(@memo, file: file, repo: @repo)

    assert_equal "diagram.svg", result[:filename]
    path = @repo.absolute_asset_path_for(@memo, "diagram.svg")
    stored = path.read
    assert_not_includes stored, "<script"
    assert_includes stored, "<circle"
  end

  test "upload preserves japanese filename" do
    file = uploaded_file("スクリーンショット.png", "image/png", "PNG")
    result = MemoAssets.upload(@memo, file: file, repo: @repo)

    assert_equal "スクリーンショット.png", result[:filename]
    assert_equal "image::スクリーンショット.png[]", result[:asciidoc]
    assert @repo.absolute_asset_path_for(@memo, "スクリーンショット.png").file?
  end

  test "upload rejects unsupported content type" do
    file = uploaded_file("evil.txt", "text/plain", "text")
    assert_raises(MemoAssets::InvalidFile) do
      MemoAssets.upload(@memo, file: file, repo: @repo)
    end
  end

  private

  def uploaded_file(name, type, body)
    tf = Tempfile.new(name)
    tf.binmode
    tf.write(body)
    tf.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: tf, filename: name, type: type)
  end
end
