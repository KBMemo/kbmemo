# frozen_string_literal: true

require "test_helper"

class WebClipTaggingTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @directory = MemoDirectory::UserSpace.clippings_directory(@account)
  end

  test "backfill tags memos in the clippings directory and descendants" do
    child = MemoDirectory.create!(parent: @directory, path_segment: "archive", label: "Archive")
    direct = create_memo(@directory, "Direct clip")
    nested = create_memo(child, "Nested clip")
    outside = create_memo(memo_directories(:work), "Outside memo")

    result = WebClipTagging.backfill!

    assert_equal 2, result.scanned
    assert_equal 0, result.already_tagged
    assert_equal 2, result.tagged
    assert_includes direct.reload.tags.pluck(:name), "web-clip"
    assert_includes nested.reload.tags.pluck(:name), "web-clip"
    assert_not_includes outside.reload.tags.pluck(:name), "web-clip"
  end

  test "backfill is idempotent and preview does not change tags" do
    memo = create_memo(@directory, "Existing clip")

    preview = WebClipTagging.backfill!(dry_run: true)
    assert_equal 1, preview.tagged
    assert_empty memo.reload.tags

    WebClipTagging.backfill!
    repeated = WebClipTagging.backfill!

    assert_equal 1, repeated.already_tagged
    assert_equal 0, repeated.tagged
  end

  private

  def create_memo(directory, title)
    Memo.create!(
      account: @account,
      memo_directory: directory,
      title: title,
      title_manual: true,
      body: "= #{title}"
    )
  end
end
