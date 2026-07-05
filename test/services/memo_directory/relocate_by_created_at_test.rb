# frozen_string_literal: true

require "test_helper"

class MemoDirectoryRelocateByCreatedAtTest < ActiveSupport::TestCase
  setup do
    @repo = MemoRepository.new
  end

  test "dry-run counts memos that would move from legacy directories" do
    memo = memos(:one)
    assert_equal "home/u-1/work", memo.memo_directory.full_path

    result = MemoDirectory::RelocateByCreatedAt.call(dry_run: true, git_relocate: false, repo: @repo)

    assert_operator result.moved, :>=, 1
    assert_equal memo.memo_directory_id, memo.reload.memo_directory_id
  end

  test "apply moves memo to created_at date directory" do
    memo = memos(:one)
    memo.update_columns(created_at: Time.zone.parse("2024-03-15 10:00:00"))
    expected = MemoDirectory::UserSpace.date_directory(memo.account_id, memo.created_at)

    MemoDirectory::RelocateByCreatedAt.call(dry_run: false, git_relocate: false, repo: @repo)

    assert_equal expected.id, memo.reload.memo_directory_id
  end

  test "apply relocates adoc and assets directory in git" do
    memo = memos(:one)
    memo.update_columns(created_at: Time.zone.parse("2024-03-15 10:00:00"), file_committed_at: Time.current)
    @repo.write_and_commit!(memo)
    @repo.write_asset!(memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD"))
    @repo.write_asset!(memo, filename: "diagrams/flow.svg", io: StringIO.new("<svg/>"))
    old_assets = @repo.assets_dir_relative_for(memo).to_s

    MemoDirectory::RelocateByCreatedAt.call(dry_run: false, git_relocate: true, repo: @repo)

    memo.reload
    new_assets = @repo.assets_dir_relative_for(memo).to_s
    assert_not_equal old_assets, new_assets
    assert @repo.root.join(new_assets, "diagrams/flow.svg").exist?
    assert_not @repo.root.join(old_assets).exist?
  end

  test "repair relocates assets left behind after adoc-only migration" do
    memo = memos(:one)
    memo.update_columns(
      created_at: Time.zone.parse("2024-03-15 10:00:00"),
      file_committed_at: Time.current
    )
    @repo.write_and_commit!(memo)
    @repo.write_asset!(memo, filename: "diagrams/flow.mmd", io: StringIO.new("graph TD"))
    @repo.write_asset!(memo, filename: "diagrams/flow.svg", io: StringIO.new("<svg/>"))

    old_assets = @repo.assets_dir_relative_for(memo).to_s
    old_adoc = @repo.relative_path_for(memo).to_s

    target = MemoDirectory::UserSpace.date_directory(memo.account_id, memo.created_at)
    memo.update_columns(memo_directory_id: target.id)
    memo.reload
    new_adoc = @repo.relative_path_for(memo).to_s
    @repo.relocate_path!(from_relative: old_adoc, to_relative: new_adoc)

    result = MemoDirectory::RelocateByCreatedAt.call(dry_run: false, git_relocate: true, repo: @repo)

    new_assets = @repo.assets_dir_relative_for(memo.reload).to_s
    assert_equal 1, result.repaired_assets
    assert @repo.root.join(new_assets, "diagrams/flow.svg").exist?
    assert_not @repo.root.join(old_assets).exist?
  end
end
