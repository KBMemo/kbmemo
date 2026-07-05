# frozen_string_literal: true

require "test_helper"

class MemoDirectoryRelocateByCreatedAtTest < ActiveSupport::TestCase
  test "dry-run counts memos that would move from legacy directories" do
    memo = memos(:one)
    assert_equal "home/u-1/work", memo.memo_directory.full_path

    result = MemoDirectory::RelocateByCreatedAt.call(dry_run: true, git_relocate: false)

    assert_operator result.moved, :>=, 1
    assert_equal memo.memo_directory_id, memo.reload.memo_directory_id
  end

  test "apply moves memo to created_at date directory" do
    memo = memos(:one)
    memo.update_columns(created_at: Time.zone.parse("2024-03-15 10:00:00"))
    expected = MemoDirectory::UserSpace.date_directory(memo.account_id, memo.created_at)

    MemoDirectory::RelocateByCreatedAt.call(dry_run: false, git_relocate: false)

    assert_equal expected.id, memo.reload.memo_directory_id
  end

  test "apply skips cleanup of empty legacy directory referenced by notebook" do
    legacy = MemoDirectory.create!(parent: memo_directories(:share_u_one), path_segment: "notebook-legacy", label: "Legacy")
    Notebook.create!(account: accounts(:one), title: "Notebook home", slug: "notebook-home", memo_directory: legacy)

    result = MemoDirectory::RelocateByCreatedAt.call(dry_run: false, git_relocate: false)

    assert legacy.reload.persisted?
    assert_empty result.errors
  end
end
