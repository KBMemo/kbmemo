# frozen_string_literal: true

require "test_helper"

class NotebooksControllerTest < ActionDispatch::IntegrationTest
  test "index lists own notebooks" do
    get notebooks_url
    assert_response :success
    assert_includes response.body, notebooks(:one).title
    assert_includes response.body, "Blog"
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

  test "show lists notebook memos for owner" do
    get notebook_url(notebooks(:one))
    assert_response :success
    assert_includes response.body, memos(:one).title
    assert_includes response.body, memos(:two).title
    assert_includes response.body, "notebook_memo_tree"
    assert_includes response.body, "notebook_memo_panel"
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
