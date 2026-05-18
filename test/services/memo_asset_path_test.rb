# frozen_string_literal: true

require "test_helper"

class MemoAssetPathTest < ActiveSupport::TestCase
  test "normalizes flat image filename" do
    assert_equal "chart.png", MemoAssetPath.normalize!("chart.png")
  end

  test "normalizes diagrams subdirectory" do
    assert_equal "diagrams/flow2.svg", MemoAssetPath.normalize!("diagrams/flow2.svg")
  end

  test "rejects path traversal" do
    assert_raises(MemoAssets::InvalidFile) { MemoAssetPath.normalize!("../secret.png") }
    assert_raises(MemoAssets::InvalidFile) { MemoAssetPath.normalize!("diagrams/../../x.svg") }
  end

  test "rejects unknown subdirectory" do
    assert_raises(MemoAssets::InvalidFile) { MemoAssetPath.normalize!("other/x.png") }
  end

  test "existing_relative keeps exact svg filename" do
    assert_equal "diagrams/[flow].svg", MemoAssetPath.existing_relative!("diagrams/[flow].svg")
    assert_equal "icon.svg", MemoAssetPath.existing_relative!("icon.svg")
  end
end
