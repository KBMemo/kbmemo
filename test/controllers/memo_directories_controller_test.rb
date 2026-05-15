# frozen_string_literal: true

require "test_helper"

class MemoDirectoriesControllerTest < ActionDispatch::IntegrationTest
  test "index lists directories" do
    get memo_directories_url
    assert_response :success
    assert_includes response.body, "ルート"
    assert_includes response.body, "home/u-1/work"
  end

  test "index hides operation links for top level buckets" do
    home = memo_directories(:home)
    work = memo_directories(:work)
    get memo_directories_url
    assert_response :success
    assert_includes response.body, "読み取り専用"
    assert_not_includes response.body, edit_memo_directory_path(home)
    assert_includes response.body, edit_memo_directory_path(work)
  end

  test "create directory under explicit parent" do
    parent = memo_directories(:home_u_one)
    assert_difference("MemoDirectory.count", 1) do
      post memo_directories_url, params: { memo_directory: { path_segment: "ideas", label: "アイデア", parent_id: parent.id } }
    end
    assert_redirected_to memo_directories_url
    d = MemoDirectory.find_by(full_path: "home/u-1/ideas")
    assert_equal "アイデア", d.label
    assert_equal parent.id, d.parent_id
  end

  test "create directory under root when parent omitted" do
    assert_difference("MemoDirectory.count", 1) do
      post memo_directories_url, params: { memo_directory: { path_segment: "brainstorm", label: "ブレスト" } }
    end
    assert_redirected_to memo_directories_url
    d = MemoDirectory.find_by(full_path: "brainstorm")
    assert_equal "ブレスト", d.label
    assert_equal memo_directories(:root).id, d.parent_id
  end

  test "cannot move directory under top level bucket" do
    work = memo_directories(:work)
    home = memo_directories(:home)
    patch memo_directory_url(work), params: { memo_directory: { label: work.label, parent_id: home.id } }
    assert_response :unprocessable_entity
    assert_equal "home/u-1/work", work.reload.full_path
  end

  test "move directory updates full_path" do
    work = memo_directories(:work)
    share_u1 = MemoDirectory.find_by!(full_path: "share/u-1")
    patch memo_directory_url(work), params: { memo_directory: { label: work.label, parent_id: share_u1.id } }
    assert_redirected_to memo_directories_url
    assert_equal "share/u-1/work", work.reload.full_path
  end

  test "cannot delete root" do
    root = memo_directories(:root)
    assert_no_difference("MemoDirectory.count") do
      delete memo_directory_url(root)
    end
    assert_redirected_to memo_directories_url
  end
end
