# frozen_string_literal: true

require "test_helper"

class MemoMetadataSuggestionsControllerTest < ActionDispatch::IntegrationTest
  test "create returns metadata suggestions" do
    fake = Object.new
    fake.define_singleton_method(:call) { { title: "提案タイトル", tags: [ "Ruby", "AI" ] } }

    MemoMetadataSuggester.stub(:new, ->(**) { fake }) do
      post metadata_suggestions_memo_url(memos(:one)),
        params: { title: "現在", body: "本文", tags: [ "Ruby" ] },
        as: :json
    end

    assert_response :success
    assert_equal(
      { "title" => "提案タイトル", "tags" => [ "Ruby", "AI" ] },
      response.parsed_body
    )
  end

  test "create is forbidden when the memo cannot be updated" do
    memo = memos(:two)
    memo.update_columns(
      account_id: accounts(:two).id,
      visibility: Memo.visibilities[:public_everyone]
    )

    post metadata_suggestions_memo_url(memo),
      params: { title: memo.title, body: memo.body, tags: [] },
      as: :json

    assert_response :forbidden
  end

  test "create returns an actionable connection error" do
    fake = Object.new
    fake.define_singleton_method(:call) do
      raise Chat::LlmClient::ConnectionError, "LLMに接続できません。"
    end

    MemoMetadataSuggester.stub(:new, ->(**) { fake }) do
      post metadata_suggestions_memo_url(memos(:one)),
        params: { title: "現在", body: "本文", tags: [] },
        as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "LLMに接続できません。", response.parsed_body["error"]
    assert response.parsed_body["settings_url"].present?
  end
end
