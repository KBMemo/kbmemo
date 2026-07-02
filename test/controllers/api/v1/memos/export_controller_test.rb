# frozen_string_literal: true

require "test_helper"

class Api::V1::Memos::ExportControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_out
    @account = accounts(:one)
    @token = @account.generate_clip_api_token!
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

  test "export deletions is not implemented yet" do
    get export_deletions_api_v1_memos_path,
      params: { deleted_since: 1.day.ago.utc.iso8601 },
      headers: auth_headers

    assert_response :not_implemented
    assert_equal "not_implemented", JSON.parse(response.body).dig("error", "code")
  end

  private

  def auth_headers
    {
      "Authorization" => "Bearer #{@token}",
      "Accept" => "application/json"
    }
  end
end
