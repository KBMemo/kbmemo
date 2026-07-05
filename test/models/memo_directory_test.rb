# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_directories
#
#  id           :bigint           not null, primary key
#  full_path    :string           not null
#  label        :string           default(""), not null
#  path_segment :string           default(""), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  parent_id    :integer
#
# Indexes
#
#  index_memo_directories_on_full_path  (full_path) UNIQUE
#  index_memo_directories_on_parent_id  (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (parent_id => memo_directories.id)
#
require "test_helper"

class MemoDirectoryTest < ActiveSupport::TestCase
  test "cascade_path_refresh updates nested full_path after parent moves" do
    work = memo_directories(:work)
    nested = MemoDirectory.create!(parent: work, path_segment: "nest", label: "Nest")
    share_u1 = MemoDirectory.find_by!(full_path: "share/u-1")

    assert_equal "home/u-1/work", work.full_path
    assert_equal "home/u-1/work/nest", nested.full_path

    work.update!(parent: share_u1)
    work.cascade_path_refresh!
    nested.reload
    assert_equal "share/u-1/work", work.reload.full_path
    assert_equal "share/u-1/work/nest", nested.full_path
  end

  test "assigns root as parent when parent_id is nil" do
    d = MemoDirectory.new(path_segment: "misc", label: "Misc")
    assert d.valid?
    assert_equal MemoDirectory.root.id, d.parent_id
    assert_equal "misc", d.full_path
  end

  test "rejects parent that is top level bucket" do
    work = memo_directories(:work)
    work.parent = memo_directories(:home)
    assert_not work.valid?
    assert_includes work.errors[:parent_id].join, "Home"
  end

  test "allows u-{id} user space root under home share public buckets" do
    home = memo_directories(:home)
    d = MemoDirectory.new(parent: home, path_segment: "u-99", label: "User 99")
    assert d.valid?, d.errors.full_messages.join(", ")
  end

  test "rejects parent that is descendant of self" do
    work = memo_directories(:work)
    nested = MemoDirectory.create!(parent: work, path_segment: "nest", label: "Nest")
    work.parent = nested
    assert_not work.valid?
    assert_includes work.errors[:parent_id].join, "配下"
  end

  test "display_name uses label or path_segment not full_path" do
    work = memo_directories(:work)
    assert_equal "仕事", work.display_name

    unlabeled = MemoDirectory.create!(parent: memo_directories(:public_u_one), path_segment: "asciidoc", label: "")
    assert_equal "asciidoc", unlabeled.display_name
    assert_equal "public/u-1/asciidoc", unlabeled.full_path
  end

  test "deletable is false when subtree has memos" do
    empty = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "empty", label: "Empty")
    assert empty.deletable?

    Memo.create!(
      account: accounts(:one),
      memo_directory: empty,
      title: "Blocked delete",
      slug: "blocked-delete-test",
      body: "body"
    )
    assert_not empty.deletable?
    assert empty.memos_in_subtree?
  end

  test "deletable is false when a board references the directory" do
    empty = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "board-dir", label: "Board dir")
    Board.create!(account: accounts(:one), title: "Linked board", memo_directory: empty)

    assert_not empty.deletable?
    assert empty.boards_in_subtree?
  end

  test "deletable is false when child directories remain" do
    empty = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "parent", label: "Parent")
    MemoDirectory.create!(parent: empty, path_segment: "nest", label: "Nest")

    assert_not empty.deletable?
    assert_not empty.memos_in_subtree?
  end

  test "delete_navigation_fallback prefers older then younger sibling then parent" do
    parent = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "nav-parent", label: "Nav parent")
    first = MemoDirectory.create!(parent: parent, path_segment: "aaa", label: "First")
    middle = MemoDirectory.create!(parent: parent, path_segment: "bbb", label: "Middle")
    MemoDirectory.create!(parent: parent, path_segment: "ccc", label: "Last")

    assert_equal first, middle.delete_navigation_fallback
    assert_equal middle, first.delete_navigation_fallback

    only_parent = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "solo-parent", label: "Solo parent")
    solo = MemoDirectory.create!(parent: only_parent, path_segment: "solo", label: "Solo")
    assert_equal only_parent, solo.delete_navigation_fallback
  end

  test "root full_path may be empty string" do
    dir = MemoDirectory.new(path_segment: "", label: "ルート", parent_id: nil)
    dir.valid?

    assert_not dir.errors.added?(:full_path, :blank)
    assert_equal "", dir.full_path
    assert dir.root?
  end

  test "ensure_root is idempotent and returns fixture root" do
    existing = memo_directories(:root)
    assert_equal existing.id, MemoDirectory.ensure_root!.id
    assert_equal existing.id, MemoDirectory.root.id
  end
end
