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
    assert_includes response.body, "memo-search-picker"
    assert_includes response.body, available_memos_notebook_path(notebooks(:one))
    assert_select "select#memo_id", count: 0
  end

  test "show renders compact selected memo title and borderless add buttons" do
    notebook = notebooks(:one)
    entry = notebook_memos(:one_one)

    get notebook_url(notebook, memo_id: entry.memo_id)
    assert_response :success
    assert_select "a.kb-notebook-tree-link.is-active[href=?]",
      notebook_path(notebook, memo_id: entry.memo_id),
      text: notebook.display_label_for_memo(entry)
    assert_select "button.kb-chrome-link.border-0.bg-transparent.p-0", text: /新規メモ/
    assert_select "button.border-0.bg-transparent.p-0[title='子メモを追加']"
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
    assert_includes response.body, "memo-search-picker"
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

  test "notebook sidebar shows the new-memo button for the owner" do
    notebook = notebooks(:one)
    get notebook_url(notebook)
    assert_response :success
    assert_select "form[action=?]", create_blank_notebook_notebook_memos_path(notebook)
  end

  test "create_blank with parent_id appends a child inheriting the parent directory and tags" do
    notebook = notebooks(:one)
    parent = notebook_memos(:one_one)
    parent_memo = parent.memo
    parent_memo.tags = [Tag.resolve_label!("InheritedTag")]
    parent_dir_id = parent_memo.memo_directory_id

    assert_difference -> { notebook.notebook_memos.where(parent_id: parent.id).count }, 1 do
      post create_blank_notebook_notebook_memos_url(notebook), params: { parent_id: parent.id }
    end

    child = notebook.notebook_memos.where(parent_id: parent.id).order(:position, :id).last
    assert_equal parent.id, child.parent_id
    assert_equal parent_dir_id, child.memo.memo_directory_id
    assert_equal ["InheritedTag"], child.memo.tags.map(&:name)
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
