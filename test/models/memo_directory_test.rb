# frozen_string_literal: true

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

  test "rejects parent that is descendant of self" do
    work = memo_directories(:work)
    nested = MemoDirectory.create!(parent: work, path_segment: "nest", label: "Nest")
    work.parent = nested
    assert_not work.valid?
    assert_includes work.errors[:parent_id].join, "配下"
  end
end
