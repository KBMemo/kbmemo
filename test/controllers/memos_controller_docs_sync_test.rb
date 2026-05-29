# frozen_string_literal: true

require "test_helper"

class MemosControllerDocsSyncTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as
    @memo = memos(:one)
    @memo.update!(
      properties: {
        "docs_sync" => {
          "source_path" => "architecture/sample.adoc",
          "read_only" => true
        }
      }
    )
  end

  test "edit redirects for docs_sync read-only memo" do
    get edit_memo_url(@memo)
    assert_redirected_to memo_url(@memo)
    assert_match "docs/", flash[:alert]
  end

  test "show displays docs sync notice" do
    get memo_url(@memo)
    assert_response :success
    assert_includes response.body, "docs/"
    assert_includes response.body, "architecture/sample.adoc"
    assert_not_includes response.body, ">編集<"
  end

  test "sidebar tab links stay on show when docs_sync memo is not file-committed" do
    @memo.update!(file_committed_at: nil)
    assert_not @memo.reload.display_as_draft?

    get memo_url(@memo)
    assert_response :success

    # タグタブはメモの先頭タグへディープリンクする（タグがあれば tag_id 付き）。
    first_tag = @memo.tags.order(:name).first
    tag_href = first_tag ? memo_path(@memo, sidebar_view: "tag", tag_id: first_tag.id) : memo_path(@memo, sidebar_view: "tag")
    assert_select ".kb-sidebar-tab-bar a[href=?]", tag_href
    assert_select ".kb-sidebar-tab-bar a[href=?]", memo_path(@memo, sidebar_view: "search")
    assert_select ".kb-sidebar-tab-bar a[href=?]", memo_path(@memo, sidebar_view: "history")
    assert_select ".kb-sidebar-tab-bar a[href*=?]", edit_memo_path(@memo), count: 0
  end

  test "sidebar tab navigation does not flash docs sync alert" do
    @memo.update!(file_committed_at: nil)

    get memo_url(@memo, sidebar_view: "search")
    assert_response :success
    assert_nil flash[:alert]
  end
end
