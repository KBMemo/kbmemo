# frozen_string_literal: true

require "test_helper"

class MemoDirectoryUserSpaceTest < ActiveSupport::TestCase
  test "clippings_directory creates home/u-{id}/clippings on first use" do
    account = accounts(:one)
    fp = "home/u-#{account.id}/clippings"
    assert_not MemoDirectory.exists?(full_path: fp)

    dir = MemoDirectory::UserSpace.clippings_directory(account)

    assert_equal fp, dir.full_path
    assert_equal "clippings", dir.path_segment
    assert_equal "クリップ", dir.label
    assert MemoDirectory.exists?(full_path: fp)
  end

  test "clippings_directory is idempotent" do
    account = accounts(:one)
    first = MemoDirectory::UserSpace.clippings_directory(account)
    second = MemoDirectory::UserSpace.clippings_directory(account)

    assert_equal first.id, second.id
  end
end
