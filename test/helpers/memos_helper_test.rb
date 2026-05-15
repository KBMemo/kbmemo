# frozen_string_literal: true

require "test_helper"

class MemosHelperTest < ActionView::TestCase
  include MemosHelper

  test "memo_directory_tree_select_option_pairs uses NBSP indent when excluding root" do
    dirs = [
      memo_directories(:root),
      memo_directories(:home),
      memo_directories(:home_u_one),
      memo_directories(:work)
    ]
    pairs = memo_directory_tree_select_option_pairs(dirs, exclude_root: true)
    work_id = memo_directories(:work).id
    work_label = pairs.find { |_l, id| id == work_id }&.first
    leading_nbsp = work_label[/\A\u00a0+/]
    assert leading_nbsp, "expected leading NBSP indent, got #{work_label.inspect}"
    assert_operator leading_nbsp.length, :>=, 4
  end

  test "memo_directory_tree_select_option_pairs exclude_root omits root id" do
    dirs = [memo_directories(:root), memo_directories(:home)]
    pairs = memo_directory_tree_select_option_pairs(dirs, exclude_root: true)
    assert_not_includes pairs.map(&:last), memo_directories(:root).id
    assert_includes pairs.map(&:last), memo_directories(:home).id
  end

  test "memo_directory_path_from_root_label joins segment labels from root" do
    home_u_one = memo_directories(:home_u_one)
    work = memo_directories(:work)
    assert_equal "/Home/User one", memo_directory_path_from_root_label(home_u_one)
    assert_equal "/Home/User one/仕事", memo_directory_path_from_root_label(work)
    assert_equal "/", memo_directory_path_from_root_label(memo_directories(:root))
  end

  test "memo_directory_tree_select_option_pairs can label root row for parent picker" do
    dirs = [memo_directories(:root), memo_directories(:home)]
    pairs = memo_directory_tree_select_option_pairs(dirs, exclude_root: false, root_option_label: "（最上位）")
    root_id = memo_directories(:root).id
    root_label = pairs.find { |_l, id| id == root_id }&.first
    assert_equal "（最上位）", root_label
  end
end
