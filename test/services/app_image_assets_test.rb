# frozen_string_literal: true

require "test_helper"

class AppImageAssetsTest < ActiveSupport::TestCase
  test "find! resolves propshaft logical path for app/assets/images file" do
    asset = AppImageAssets.find!("octocat.jpg")
    assert_equal "octocat.jpg", asset.logical_path.to_s
    assert asset.path.file?
  end

  test "find! accepts /images/ macro prefix" do
    asset = AppImageAssets.find!("/images/octocat.jpg")
    assert_equal "octocat.jpg", asset.logical_path.to_s
  end

  test "public_path returns digested assets url" do
    path = AppImageAssets.public_path("octocat.jpg")
    assert_match %r{\A/assets/octocat-[0-9a-f]+\.jpg\z}, path
  end

  test "find! rejects path traversal" do
    assert_raises(AppImageAssets::Missing) { AppImageAssets.find!("../octocat.jpg") }
  end
end
