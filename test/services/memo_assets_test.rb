# frozen_string_literal: true

require "test_helper"

class MemoAssetsTest < ActiveSupport::TestCase
  setup do
    @memo = memos(:one)
    @memo.update_columns(slug: "first-memo-#{@memo.id}")
    @repo = MemoRepository.new
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
