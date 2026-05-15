# frozen_string_literal: true

require "test_helper"

class MemosHelperTest < ActionView::TestCase
  include MemosHelper
  include Pundit::Authorization

  def pundit_user
    accounts(:one)
  end

  def policy_scope(scope)
    MemoPolicy::Scope.new(pundit_user, scope).resolve
  end

  test "memo_wiki_link_reference builds full_path and slug" do
    memo = memos(:two)
    work = memo_directories(:work)
    memo.update_columns(memo_directory_id: work.id, slug: "second-memo")
    assert_equal "[[#{work.full_path}/second-memo]]", memo_wiki_link_reference_for(memo)
  end

  test "memo_wiki_link_reference_for returns nil without directory" do
    memo = memos(:one)
    memo.update_columns(memo_directory_id: memo_directories(:root).id, slug: "x")
    assert_nil memo_wiki_link_reference_for(memo)
  end

  test "memo_html converts wiki link to memo href" do
    html = memo_html("See [[Second memo]].", source_memo: memos(:one))
    assert_includes html, %(href="/memos/#{memos(:two).id}")
    assert_includes html, "Second memo"
  end

  test "memo_html renders broken wiki link with styled span" do
    html = memo_html("[[no-such-memo]]", source_memo: memos(:one))
    assert_includes html, 'class="memo-wiki-broken"'
    assert_includes html, "no-such-memo"
    assert_not_includes html, "&lt;span"
  end

  test "memo_html leaves wiki syntax inside fenced code" do
    body = "```\n[[Second memo]]\n```\n\n[[Second memo]]"
    html = memo_html(body, source_memo: memos(:one))
    assert_includes html, "[[Second memo]]"
    assert_includes html, %(href="/memos/#{memos(:two).id}")
  end

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
