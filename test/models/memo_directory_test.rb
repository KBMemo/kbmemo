# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_directories
#
#  id           :integer          not null, primary key
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
#  parent_id  (parent_id => memo_directories.id)
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

  test "rejects parent that is descendant of self" do
    work = memo_directories(:work)
    nested = MemoDirectory.create!(parent: work, path_segment: "nest", label: "Nest")
    work.parent = nested
    assert_not work.valid?
    assert_includes work.errors[:parent_id].join, "配下"
  end
end
