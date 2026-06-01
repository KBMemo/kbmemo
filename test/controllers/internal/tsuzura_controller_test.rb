# frozen_string_literal: true

require "test_helper"

class Internal::TsuzuraControllerTest < ActionDispatch::IntegrationTest
  setup do
    @memo = memos(:one)
    @memo.update!(visibility: :public_everyone)
    @ulid = ULID.generate.to_s
  end

  test "authorize returns signed urls for public memo when logged in" do
    post internal_tsuzura_authorize_path,
      params: { memo_id: @memo.id, media_ids: [ @ulid ] },
      as: :json
    assert_response :success
    body = response.parsed_body
    assert body["urls"].key?(@ulid)
    assert_includes body["urls"][@ulid], @ulid
  end

  test "authorize rejects private memo for other user" do
    memo = memos(:two)
    post internal_tsuzura_authorize_path,
      params: { memo_id: memo.id, media_ids: [ @ulid ] },
      as: :json
    assert_response :forbidden
  end
end
