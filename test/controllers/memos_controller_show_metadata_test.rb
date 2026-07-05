# frozen_string_literal: true

require "test_helper"

class MemosControllerShowMetadataTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(:one)
    @memo = memos(:one)
    @other_dir = memo_directories(:share_u_one)
  end

  test "update_directory is disabled" do
    original = @memo.memo_directory_id

    patch update_directory_memo_path(@memo),
      params: { memo_directory_id: @other_dir.id },
      as: :json

    assert_response :unprocessable_entity
    assert_equal original, @memo.reload.memo_directory_id
  end

  test "update_tags adds and removes tags via turbo stream" do
    patch update_tags_memo_path(@memo),
      params: { tag_list: "alpha, beta" },
      headers: { Accept: "text/vnd.turbo-stream.html" },
      as: :json

    assert_response :success
    @memo.reload
    assert_equal %w[alpha beta], @memo.tags.order(:name).pluck(:name)

    patch update_tags_memo_path(@memo),
      params: { tag_list: "alpha" },
      headers: { Accept: "text/vnd.turbo-stream.html" },
      as: :json

    assert_response :success
    @memo.reload
    assert_equal [ "alpha" ], @memo.tags.pluck(:name)
  end

  test "update_tags turbo stream includes commit button for draft memo" do
    t = 1.hour.ago.change(usec: 0)
    @memo.update_columns(file_committed_at: t, updated_at: t)

    patch update_tags_memo_path(@memo),
      params: { tag_list: "draft-tag" },
      headers: { Accept: "text/vnd.turbo-stream.html" },
      as: :json

    assert_response :success
    assert_includes response.body, commit_memo_path(@memo)
    assert_includes response.body, ">コミット<"
  end
end
