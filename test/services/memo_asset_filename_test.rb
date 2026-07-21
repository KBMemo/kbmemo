# frozen_string_literal: true

require "test_helper"

class MemoAssetFilenameTest < ActiveSupport::TestCase
  test "preserves japanese characters" do
    assert_equal "スクリーンショット.png", MemoAssetFilename.sanitize("スクリーンショット.png")
    assert_equal "図1_説明.jpg", MemoAssetFilename.sanitize("図1 説明.jpg")
  end

  test "normalizes to NFC" do
    nfd = "か\u3099き.png" # か + 結合濁点
    nfc = MemoAssetFilename.sanitize(nfd)
    assert_equal "\u304C\u304D.png", nfc
  end

  test "strips path components and forbidden characters" do
    assert_equal "evil.png", MemoAssetFilename.sanitize("../../evil.png")
    assert_equal "a_b.png", MemoAssetFilename.sanitize("a<b>.png")
    assert_equal "file_1.png", MemoAssetFilename.sanitize("file[1].png")
  end

  test "falls back when name is empty after sanitize" do
    assert_equal "image.png", MemoAssetFilename.sanitize("///")
    assert_equal "image.png", MemoAssetFilename.sanitize("   ")
  end
end
