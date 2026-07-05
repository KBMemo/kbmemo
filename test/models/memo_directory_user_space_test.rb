# frozen_string_literal: true

require "test_helper"

class MemoDirectoryUserSpaceTest < ActiveSupport::TestCase
  test "date_directory creates home/u-{id}/YYYY-MM-DD on first use" do
    account = accounts(:one)
    time = Time.zone.parse("2025-07-05 23:30:00 +0900")
    fp = "home/u-#{account.id}/2025-07-05"
    assert_not MemoDirectory.exists?(full_path: fp)

    dir = MemoDirectory::UserSpace.date_directory(account, time)

    assert_equal fp, dir.full_path
    assert_equal "2025-07-05", dir.path_segment
    assert_equal "2025-07-05", dir.label
  end

  test "date_directory is idempotent" do
    account = accounts(:one)
    first = MemoDirectory::UserSpace.date_directory(account, Time.zone.parse("2025-07-05 12:00:00"))
    second = MemoDirectory::UserSpace.date_directory(account, Time.zone.parse("2025-07-05 18:00:00"))

    assert_equal first.id, second.id
  end

  test "date_segment_for uses Asia/Tokyo" do
    utc_evening = Time.utc(2025, 7, 5, 15, 0, 0)
    assert_equal "2025-07-06", MemoDirectory::UserSpace.date_segment_for(utc_evening)
  end

  test "relocatable_memo? excludes docs sync and reserved paths" do
    memo = memos(:one)
    assert MemoDirectory::UserSpace.relocatable_memo?(memo)

    memo.properties = { "docs_sync" => { "source_path" => "x.adoc" } }
    assert_not MemoDirectory::UserSpace.relocatable_memo?(memo)
  end

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
