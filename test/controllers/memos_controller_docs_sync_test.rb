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
end
