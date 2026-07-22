# frozen_string_literal: true

require "test_helper"

class Api::V1::Memos::ExportControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_out
    @account = accounts(:one)
    @token = @account.generate_api_token!
    @memo = memos(:one)
  end

  test "export returns committed memos" do
    get export_api_v1_memos_path, headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    uids = body.fetch("memos").map { |row| row["uid"] }
    assert_includes uids, @memo.uid
    assert body.dig("pagination", "has_more").in?([ true, false ])
  end

  test "export filters by updated_since" do
    get export_api_v1_memos_path,
      params: { updated_since: 1.day.from_now.utc.iso8601 },
      headers: auth_headers

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("memos")
  end

  test "export excludes drafts by default and includes them when requested" do
    draft = Memo.create!(
      account: @account,
      memo_directory: @memo.memo_directory,
      title: "Draft export memo",
      body: "= Draft",
      file_committed_at: nil
    )

    get export_api_v1_memos_path, headers: auth_headers

    assert_response :success
    uids = JSON.parse(response.body).fetch("memos").map { |row| row["uid"] }
    assert_not_includes uids, draft.uid

    get export_api_v1_memos_path, params: { include_drafts: true }, headers: auth_headers

    assert_response :success
    uids = JSON.parse(response.body).fetch("memos").map { |row| row["uid"] }
    assert_includes uids, draft.uid
  end

  test "export only returns group memos visible to token account" do
    visible = Memo.create!(
      account: accounts(:one),
      memo_directory: memo_directories(:work),
      title: "Alpha export memo",
      body: "= Alpha shared",
      visibility: :group_read,
      memo_group: memo_groups(:alpha),
      file_committed_at: Time.current
    )
    hidden = Memo.create!(
      account: accounts(:two),
      memo_directory: memo_directories(:home_u_two),
      title: "Beta export memo",
      body: "= Beta shared",
      visibility: :group_read,
      memo_group: memo_groups(:beta),
      file_committed_at: Time.current
    )
    token = accounts(:two).generate_api_token!

    get export_api_v1_memos_path, headers: auth_headers(token: token)

    assert_response :success
    uids = JSON.parse(response.body).fetch("memos").map { |row| row["uid"] }
    assert_includes uids, visible.uid
    assert_includes uids, hidden.uid

    get export_api_v1_memos_path, headers: auth_headers

    assert_response :success
    uids = JSON.parse(response.body).fetch("memos").map { |row| row["uid"] }
    assert_includes uids, visible.uid
    assert_not_includes uids, hidden.uid
  end

  test "export deletions returns deleted memo tombstones" do
    deleted_uid = @memo.uid
    @memo.destroy!

    get export_deletions_api_v1_memos_path,
      params: { deleted_since: 1.day.ago.utc.iso8601 },
      headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ deleted_uid ], body.fetch("deletions").map { |row| row["uid"] }
    assert_equal @memo.id, body.fetch("deletions").first["id"]
    assert body.dig("pagination", "has_more").in?([ true, false ])
  end

  test "export deletions filters by deleted_since" do
    @memo.destroy!

    get export_deletions_api_v1_memos_path,
      params: { deleted_since: 1.day.from_now.utc.iso8601 },
      headers: auth_headers

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("deletions")
  end

  test "export deletions paginates by cursor" do
    deleted_uids = []
    3.times do |index|
      memo = Memo.create!(
        account: @account,
        memo_directory: @memo.memo_directory,
        title: "削除テスト #{index}",
        body: "本文 #{index}",
        file_committed_at: Time.current
      )
      deleted_uids << memo.uid
      memo.destroy!
    end

    get export_deletions_api_v1_memos_path,
      params: { deleted_since: 1.day.ago.utc.iso8601, limit: 2 },
      headers: auth_headers

    assert_response :success
    first_page = JSON.parse(response.body)
    assert_equal 2, first_page.fetch("deletions").size
    assert first_page.dig("pagination", "has_more")

    get export_deletions_api_v1_memos_path,
      params: {
        deleted_since: 1.day.ago.utc.iso8601,
        limit: 2,
        cursor: first_page.dig("pagination", "next_cursor")
      },
      headers: auth_headers

    assert_response :success
    second_page = JSON.parse(response.body)
    assert_equal [ deleted_uids.last ], second_page.fetch("deletions").map { |row| row["uid"] }
    assert_not second_page.dig("pagination", "has_more")
  end

  test "export deletions requires valid deleted_since" do
    get export_deletions_api_v1_memos_path,
      params: { deleted_since: "invalid" },
      headers: auth_headers

    assert_response :unprocessable_entity
    assert_equal "validation_error", JSON.parse(response.body).dig("error", "code")
  end

  private

  def auth_headers(token: @token)
    {
      "Authorization" => "Bearer #{token}",
      "Accept" => "application/json"
    }
  end
end
