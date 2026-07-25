# frozen_string_literal: true

require "test_helper"

class NotebooksControllerTest < ActionDispatch::IntegrationTest
  test "index lists own notebooks" do
    get notebooks_url
    assert_response :success
    assert_includes response.body, notebooks(:one).title
    assert_includes response.body, "Blog"
    assert_select "[data-user-menu-target='panel'] a[href=?]", notebook_path(notebooks(:one))
    assert_select "[data-user-menu-target='panel'] a[href=?]", notebooks_path
  end

  test "create notebook" do
    assert_difference("Notebook.count", 1) do
      post notebooks_url, params: {
        notebook: {
          title: "My notes",
          slug: "my-notes",
          publication_kind: "notes",
          description: "Personal"
        }
      }
    end
    notebook = Notebook.order(:id).last
    assert_redirected_to notebook_url(notebook)
    assert notebook.notes?
  end

  test "create notebook renders accessible field errors" do
    assert_no_difference("Notebook.count") do
      post notebooks_url, params: {
        notebook: {
          title: "",
          slug: "invalid-title",
          publication_kind: "notes"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "input#notebook_title[aria-invalid='true'][aria-describedby='notebook_title_error']"
    assert_select "#notebook_title_error"
  end

  test "show lists notebook memos for owner" do
    get notebook_url(notebooks(:one))
    assert_response :success
    assert_includes response.body, memos(:one).title
    assert_includes response.body, memos(:two).title
    assert_includes response.body, "notebook_memo_tree"
    assert_includes response.body, "notebook_memo_panel"
    assert_not_includes response.body, "memo-search-picker"
    assert_includes response.body, available_memos_notebook_path(notebooks(:one))
    assert_select "select#memo_id", count: 0
    assert_select "dialog input#notebook_dialog_memo_picker[type='search']"
    assert_select "body.kb-notebook-viewport"
    assert_select "main.kb-notebook-main"
    assert_select ".kb-notebook-workspace"
    assert_select "#notebook_sidebar_shell.kb-notebook-sidebar-shell"
    assert_select "#notebook_memo_panel.kb-notebook-content-scroll"
    assert_select "#notebook_sidebar_shell a[href=?]", notebooks_path, count: 0
    assert_select "#notebook_sidebar_shell a.kb-toolbar-btn[href=?][aria-label='ノートブックを編集'][title='ノートブックを編集']",
      edit_notebook_path(notebooks(:one)) do
      assert_select "i[data-lucide='pencil'][aria-hidden='true']"
    end
    assert_select "#notebook_sidebar_shell form[action=?]", unpublish_notebook_path(notebooks(:one)), count: 0
  end

  test "edit keeps publication actions out of the sidebar workflow" do
    published = notebooks(:one)
    get edit_notebook_url(published)
    assert_response :success
    assert_select "section", text: /公開設定/ do
      assert_select "form[action=?] button", unpublish_notebook_path(published), text: "公開停止"
    end

    draft = notebooks(:two)
    get edit_notebook_url(draft)
    assert_response :success
    assert_select "section", text: /公開設定/ do
      assert_select "form[action=?] button", publish_notebook_path(draft), text: "公開"
    end
  end

  test "show renders compact selected memo title and borderless add buttons" do
    notebook = notebooks(:one)
    entry = notebook_memos(:one_one)
    child = notebook_memos(:one_two)
    child.update!(parent: entry)

    get notebook_url(notebook, memo_id: entry.memo_id)
    assert_response :success
    assert_select "a.kb-notebook-tree-link.is-active[href=?]",
      notebook_path(notebook, memo_id: entry.memo_id),
      text: notebook.display_label_for_memo(entry)
    assert_select "#notebook_sidebar_shell", text: /新規メモ/, count: 0
    assert_select "button.border-0.bg-transparent.p-0[title='子メモを追加']"
    child_search_label = "「#{notebook.display_label_for_memo(entry)}」の子階層に既存メモを追加"
    assert_select "button.kb-notebook-tree-row-search-button[aria-label=?][data-notebook-memo-picker-dialog-parent-id-param=?]",
      child_search_label,
      entry.id.to_s do
      assert_select "i[data-lucide='search'][aria-hidden='true']"
    end
    assert_select "li.kb-notebook-tree-add-row", count: 2
    assert_select "button.kb-notebook-tree-add-button.justify-center[aria-label='最上位に新規メモを追加']" do
      assert_select "i[data-lucide='plus'][aria-hidden='true']"
    end
    assert_select "button.kb-notebook-tree-search-button[aria-label='最上位に既存メモを追加']" do
      assert_select "i[data-lucide='search'][aria-hidden='true']"
    end
    assert_select "dialog#notebook_memo_picker_dialog[aria-labelledby='notebook-memo-picker-dialog-title']"
    assert_select "dialog form[action=?] input[name='parent_id'][data-notebook-memo-picker-dialog-target='parentId']",
      notebook_notebook_memos_path(notebook)
    assert_select "dialog button[type='submit'][aria-label='追加'][title='追加'][disabled]" do
      assert_select "i[data-lucide='plus'][aria-hidden='true']"
    end
    assert_select "dialog button[type='button'][aria-label='キャンセル'][title='キャンセル']" do
      assert_select "i[data-lucide='x'][aria-hidden='true']"
    end
    sibling_label = "「#{notebook.display_label_for_memo(child)}」と同じ階層に新規メモを追加"
    assert_select "button.kb-notebook-tree-add-button[aria-label=?]", sibling_label
    assert_select "form[action=?] input[name='parent_id'][value=?]",
      create_blank_notebook_notebook_memos_path(notebook),
      entry.id.to_s
    assert_select "summary.kb-notebook-tree-summary", minimum: 1
    assert_select "summary.memo-directory-nav-summary", count: 0
  end

  test "available_memos returns unassigned memos filtered by query" do
    notebook = notebooks(:one)
    unassigned = memos(:two)
    unassigned.notebook_memo&.destroy

    get available_memos_notebook_url(notebook), params: { q: "Second" }, headers: { Accept: "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert(body.any? { |row| row["id"] == unassigned.id })
    assert body.all? { |row| row.key?("id") && row.key?("title") }
  end

  test "available_memos includes docs_sync read-only memo assigned to another notebook" do
    dev_notebook = notebooks(:one)
    target_notebook = notebooks(:two)
    memo = memos(:one)
    memo.notebook_memo&.destroy
    memo.update!(
      title: "AsciiDoc Dev Docs Sample",
      visibility: :group_read,
      memo_group_id: memo_groups(:alpha).id,
      account: accounts(:one),
      properties: {
        "docs_sync" => {
          "source_path" => "architecture/asciidoc-sample.adoc",
          "read_only" => true
        }
      }
    )
    NotebookMemo.create!(notebook: dev_notebook, memo: memo, position: 99)

    get available_memos_notebook_url(target_notebook), params: { q: "AsciiDoc" },
      headers: { Accept: "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert(body.any? { |row| row["id"] == memo.id && row["title"].include?("AsciiDoc") })
  end

  test "available_memos excludes docs_sync read-only memo already in target notebook" do
    notebook = notebooks(:one)
    memo = memos(:two)
    memo.notebook_memo&.destroy
    memo.update!(
      title: "AsciiDoc Already Here",
      properties: {
        "docs_sync" => {
          "source_path" => "architecture/already-here.adoc",
          "read_only" => true
        }
      }
    )
    NotebookMemo.create!(notebook: notebook, memo: memo, position: 99)

    get available_memos_notebook_url(notebook), params: { q: "AsciiDoc" },
      headers: { Accept: "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_not(body.any? { |row| row["id"] == memo.id })
  end

  test "add docs_sync read-only memo moves from another notebook" do
    dev_notebook = notebooks(:one)
    target_notebook = notebooks(:two)
    memo = memos(:one)
    memo.notebook_memo&.destroy
    memo.update!(
      properties: {
        "docs_sync" => {
          "source_path" => "architecture/move-me.adoc",
          "read_only" => true
        }
      }
    )
    NotebookMemo.create!(notebook: dev_notebook, memo: memo, position: 0)

    assert_difference -> { target_notebook.notebook_memos.count }, 1 do
      assert_difference -> { dev_notebook.notebook_memos.where(memo: memo).count }, -1 do
        post notebook_notebook_memos_url(target_notebook), params: { memo_id: memo.id }
      end
    end
    assert_redirected_to notebook_path(target_notebook, memo_id: memo.id)
  end

  test "show selects memo from query param" do
    get notebook_url(notebooks(:one), memo_id: memos(:two).id)
    assert_response :success
    assert_includes response.body, memos(:two).title
  end

  test "show renders overview when notebook has no memos" do
    notebook = Notebook.create!(
      account: accounts(:one),
      title: "Empty notebook",
      slug: "empty-notebook",
      publication_kind: :notes
    )

    get notebook_url(notebook)
    assert_response :success
    assert_includes response.body, "Empty notebook"
    assert_includes response.body, "左の一覧からメモを選ぶ"
    assert_not_includes response.body, "memo-search-picker"
    assert_select "li.kb-notebook-tree-add-row", count: 1
    assert_select "button.kb-notebook-tree-add-button[aria-label='最上位に新規メモを追加']"
  end

  test "reorder memos in tree" do
    notebook = notebooks(:one)
    entry = notebook_memos(:one_two)

    patch reorder_memos_notebook_url(notebook), params: {
      notebook_memo_id: entry.id,
      parent_id: notebook_memos(:one_one).id,
      position: 0
    }, as: :json

    assert_response :no_content
    assert_equal notebook_memos(:one_one).id, entry.reload.parent_id
  end

  test "publish blog notebook" do
    notebook = notebooks(:two)
    assert_nil notebook.published_at

    patch publish_notebook_url(notebook)
    assert_redirected_to notebook_url(notebook)
    assert notebook.reload.published?
  end

  test "cannot publish notes notebook" do
    notebook = notebooks(:one)
    notebook.update_columns(publication_kind: Notebook.publication_kinds[:notes], published_at: nil)

    patch publish_notebook_url(notebook)
    assert_redirected_to notebook_url(notebook)
    assert_nil notebook.reload.published_at
  end

  test "guest can view published manual notebook" do
    sign_out
    notebook = notebooks(:one)
    notebook.update_columns(publication_kind: Notebook.publication_kinds[:manual], published_at: Time.current)
    memos(:one).update_columns(visibility: Memo.visibilities[:public_everyone])
    memos(:two).update_columns(visibility: Memo.visibilities[:public_everyone])

    get notebook_url(notebook)
    assert_response :success
    assert_includes response.body, notebook.title
    assert_select "li.kb-notebook-tree-add-row", count: 0
  end

  test "add memo to notebook" do
    notebook = notebooks(:two)
    memo = memos(:one)
    memo.notebook_memo&.destroy

    assert_difference -> { notebook.notebook_memos.count }, 1 do
      post notebook_notebook_memos_url(notebook), params: { memo_id: memo.id }
    end
    assert_redirected_to notebook_path(notebook, memo_id: memo.id)
  end

  test "add memo to a selected notebook tree hierarchy" do
    notebook = notebooks(:one)
    parent = notebook_memos(:one_one)
    memo = memos(:two)
    memo.notebook_memo&.destroy

    assert_difference -> { notebook.notebook_memos.where(parent_id: parent.id).count }, 1 do
      post notebook_notebook_memos_url(notebook), params: { memo_id: memo.id, parent_id: parent.id }
    end

    assert_equal parent.id, notebook.notebook_memos.find_by!(memo: memo).parent_id
    assert_redirected_to notebook_path(notebook, memo_id: memo.id)
  end

  test "create_blank creates a new memo and appends it to the notebook end" do
    notebook = notebooks(:one)
    last_position = notebook.notebook_memos.where(parent_id: nil).maximum(:position).to_i

    assert_difference -> { Memo.count }, 1 do
      assert_difference -> { notebook.notebook_memos.count }, 1 do
        post create_blank_notebook_notebook_memos_url(notebook)
      end
    end

    new_entry = notebook.notebook_memos.order(:position, :id).last
    assert_nil new_entry.parent_id
    assert_equal last_position + 1, new_entry.position
    assert_redirected_to edit_memo_path(new_entry.memo_id)
  end

  test "notebook sidebar keeps memo creation actions in the tree" do
    notebook = notebooks(:one)
    get notebook_url(notebook)
    assert_response :success
    assert_select "#notebook_sidebar_shell", text: /新規メモ/, count: 0
    assert_select "button.kb-notebook-tree-add-button", minimum: 1
    assert_select "button.kb-notebook-tree-search-button", minimum: 1
  end

  test "create_blank with parent_id appends a child with date directory and inherited tags" do
    notebook = notebooks(:one)
    parent = notebook_memos(:one_one)
    parent_memo = parent.memo
    parent_memo.tags = [ Tag.resolve_label!("InheritedTag") ]

    assert_difference -> { notebook.notebook_memos.where(parent_id: parent.id).count }, 1 do
      post create_blank_notebook_notebook_memos_url(notebook), params: { parent_id: parent.id }
    end

    child = notebook.notebook_memos.where(parent_id: parent.id).order(:position, :id).last
    assert_equal parent.id, child.parent_id
    expected_dir = MemoDirectory::UserSpace.date_directory(child.memo.account_id, child.memo.created_at)
    assert_equal expected_dir.id, child.memo.memo_directory_id
    assert_equal [ "InheritedTag" ], child.memo.tags.map(&:name)
    assert_redirected_to edit_memo_path(child.memo_id)
  end

  test "create_blank ignores a parent_id from another notebook" do
    notebook = notebooks(:one)
    foreign_parent = notebook_memos(:one_one)
    other_notebook = notebooks(:two)

    post create_blank_notebook_notebook_memos_url(other_notebook), params: { parent_id: foreign_parent.id }
    assert_response :redirect

    new_entry = other_notebook.notebook_memos.order(:created_at, :id).last
    assert_nil new_entry.parent_id
  end

  test "notebook tree rows render a child-add button carrying the parent_id" do
    notebook = notebooks(:one)
    get notebook_url(notebook)
    assert_response :success
    assert_select "form[action=?] input[name=?][value=?]",
      create_blank_notebook_notebook_memos_path(notebook),
      "parent_id",
      notebook_memos(:one_one).id.to_s
  end

  test "add docs_sync read-only memo to notebook when user can view but not edit" do
    notebook = notebooks(:two)
    memo = memos(:two)
    memo.notebook_memo&.destroy
    memo.update!(
      visibility: :group_read,
      memo_group_id: memo_groups(:alpha).id,
      account: accounts(:one),
      properties: {
        "docs_sync" => {
          "source_path" => "architecture/dev-docs-sample.adoc",
          "read_only" => true
        }
      }
    )

    assert_not MemoPolicy.new(accounts(:one), memo).update?
    assert MemoPolicy.new(accounts(:one), memo).add_to_notebook?

    assert_difference -> { notebook.notebook_memos.count }, 1 do
      post notebook_notebook_memos_url(notebook), params: { memo_id: memo.id }
    end
    assert_redirected_to notebook_path(notebook, memo_id: memo.id)

    get notebook_url(notebook, memo_id: memo.id)
    assert_response :success
    assert_select "a[href=?]", edit_memo_path(memo), count: 0
    assert_includes response.body, "docs/"
  end

  test "cannot access other users notebook when unpublished" do
    other = Notebook.create!(
      title: "Private",
      slug: "private-nb",
      publication_kind: :notes,
      account: accounts(:two)
    )
    get notebook_url(other)
    assert_response :not_found
  end
end
