# frozen_string_literal: true

require "test_helper"

class Internal::TsuzuraControllerTest < ActionDispatch::IntegrationTest
  setup do
    @memo = memos(:one)
    @memo.update!(visibility: :public_everyone)
    @ulid = ULID.generate.to_s
  end

  test "authorize returns signed urls for public memo when logged in" do
    post internal_tsuzura_sign_urls_path,
      params: { memo_id: @memo.id, media_ids: [ @ulid ] },
      as: :json
    assert_response :success
    body = response.parsed_body
    assert body["urls"].key?(@ulid)
    assert_includes body["urls"][@ulid], @ulid
  end

  test "authorize returns album media ids for album_ids" do
    album_id = ULID.generate.to_s
    media_id = ULID.generate.to_s
    Tsuzura::Client.stub(:fetch_album, { "media_item_ids" => [ media_id ] }) do
      post internal_tsuzura_sign_urls_path,
        params: { memo_id: @memo.id, album_ids: [ album_id ] },
        as: :json
      assert_response :success
      body = response.parsed_body
      assert_equal [ media_id.upcase ], body.dig("albums", album_id.upcase)
      assert body["urls"].key?(media_id.upcase)
    end
  end

  test "authorize rejects private memo for other user" do
    memo = memos(:two)
    post internal_tsuzura_sign_urls_path,
      params: { memo_id: memo.id, media_ids: [ @ulid ] },
      as: :json
    assert_response :forbidden
  end
end
