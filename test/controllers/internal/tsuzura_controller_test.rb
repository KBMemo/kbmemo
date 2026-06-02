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

  test "albums returns list for logged in user" do
    Tsuzura::Client.stub(:list_albums, { "albums" => [ { "id" => ULID.generate.to_s, "title" => "A" } ] }) do
      get internal_tsuzura_albums_path, as: :json
      assert_response :success
      assert_equal 1, response.parsed_body["albums"].size
    end
  end

  test "albums returns service unavailable when Tsuzura is unreachable" do
    Tsuzura::Client.stub(:list_albums, nil) do
      get internal_tsuzura_albums_path, as: :json
      assert_response :service_unavailable
      assert_equal [], response.parsed_body["albums"]
      assert response.parsed_body["error"].present?
    end
  end

  test "album returns album payload for owner" do
    album_id = ULID.generate.to_s
    Tsuzura::Client.stub(
      :fetch_album,
      { "id" => album_id, "title" => "Trip", "owner_account_id" => accounts(:one).id, "media_item_ids" => [] }
    ) do
      get internal_tsuzura_album_path(album_id), as: :json
      assert_response :success
      assert_equal album_id, response.parsed_body["id"]
    end
  end

  test "album rejects other owner" do
    album_id = ULID.generate.to_s
    Tsuzura::Client.stub(
      :fetch_album,
      { "id" => album_id, "owner_account_id" => accounts(:two).id, "media_item_ids" => [] }
    ) do
      get internal_tsuzura_album_path(album_id), as: :json
      assert_response :forbidden
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
