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

  test "cannot delete directory with memos" do
    sign_in_as
    dir = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "with-memo", label: "With memo")
    Memo.create!(
      account: accounts(:one),
      memo_directory: dir,
      title: "Keep me",
      slug: "keep-me-delete-test",
      body: "body"
    )

    assert_no_difference("MemoDirectory.count") do
      delete memo_directory_url(dir)
    end
    assert_redirected_to memo_directories_url
    assert_equal "メモが残っているディレクトリは削除できません。", flash[:alert]
  end

  test "cannot delete directory with child directories" do
    sign_in_as
    parent = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "parent-del", label: "Parent del")
    MemoDirectory.create!(parent: parent, path_segment: "nest", label: "Nest")

    assert_no_difference("MemoDirectory.count") do
      delete memo_directory_url(parent)
    end
    assert_redirected_to memo_directories_url
    assert_equal "子ディレクトリが残っているため削除できません。", flash[:alert]
  end

  test "cannot delete directory with board reference" do
    sign_in_as
    dir = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "board-linked", label: "Board linked")
    Board.create!(account: accounts(:one), title: "Uses dir", memo_directory: dir)

    assert_no_difference("MemoDirectory.count") do
      delete memo_directory_url(dir)
    end
    assert_redirected_to memo_directories_url
    assert_equal "ボードの保存先に指定されているディレクトリは削除できません。", flash[:alert]
  end

  test "sidebar delete refreshes panel and redirects to older sibling" do
    sign_in_as
    parent = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "del-parent", label: "Del parent")
    older = MemoDirectory.create!(parent: parent, path_segment: "aaa", label: "Older")
    target = MemoDirectory.create!(parent: parent, path_segment: "bbb", label: "Target")

    assert_difference("MemoDirectory.count", -1) do
      delete memo_directory_url(target,
        params: {
          sidebar: "1",
          current_memo_directory_id: target.id,
          nav_open_directory_ids: [ parent.id ]
        },
        as: :turbo_stream)
    end

    assert_response :success
    assert_includes response.body, 'target="memos_list_panel"'
    assert_equal memos_path(memo_directory_id: older.id), response.headers["X-Sidebar-Redirect"]
  end

  test "sidebar delete does not redirect when another directory is selected" do
    sign_in_as
    parent = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "keep-parent", label: "Keep parent")
    keep = MemoDirectory.create!(parent: parent, path_segment: "keep", label: "Keep")
    target = MemoDirectory.create!(parent: parent, path_segment: "drop", label: "Drop")

    delete memo_directory_url(target,
      params: {
        sidebar: "1",
        current_memo_directory_id: keep.id,
        nav_open_directory_ids: [ parent.id ]
      },
      as: :turbo_stream)

    assert_response :success
    assert_nil response.headers["X-Sidebar-Redirect"]
  end

  test "dialog new renders form partial" do
    parent = memo_directories(:home_u_one)
    get new_memo_directory_url(parent_id: parent.id, dialog: 1)
    assert_response :success
    assert_includes response.body, "子ディレクトリを追加"
    assert_includes response.body, 'name="dialog"'
    assert_includes response.body, "/Home/User one"
  end

  test "dialog edit renders form partial" do
    work = memo_directories(:work)
    get edit_memo_directory_url(work, dialog: 1)
    assert_response :success
    assert_includes response.body, "ディレクトリを編集"
    assert_includes response.body, 'name="dialog"'
  end

  test "dialog create refreshes sidebar via turbo stream" do
    parent = memo_directories(:home_u_one)
    public_dir = memo_directories(:public)
    post memo_directories_url,
      params: {
        dialog: "1",
        sidebar_view: "directory",
        nav_open_directory_ids: [ public_dir.id ],
        memo_directory: { path_segment: "sidebar-child", label: "Sidebar child", parent_id: parent.id }
      },
      as: :turbo_stream
    assert_response :success
    assert_includes response.media_type, "text/vnd.turbo-stream.html"
    assert_includes response.body, 'target="memos_list_panel"'
    assert_includes response.body, "Sidebar child"
    assert_includes response.body,
      %(data-memo-directory-id="#{public_dir.id}" data-memo-directory-nav-branch="" data-memo-directory-nav-open="true")
    assert MemoDirectory.find_by(full_path: "home/u-1/sidebar-child")
  end
end
