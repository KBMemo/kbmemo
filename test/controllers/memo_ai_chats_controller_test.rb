# frozen_string_literal: true

require "test_helper"

class MemoAiChatsControllerTest < ActionDispatch::IntegrationTest
  test "create returns reply when api key configured" do
    accounts(:one).update!(openai_api_key: "sk-test")
    memo = memos(:one)

    fake = Object.new
    fake.define_singleton_method(:call) { { reply: "== AI section\n\nContent" } }

    original_new = MemoAiChat.method(:new)
    begin
      MemoAiChat.define_singleton_method(:new) { |**_kwargs| fake }

      post ai_chat_memo_url(memo),
        params: { messages: [ { role: "user", content: "見出しを追加" } ] },
        as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "== AI section\n\nContent", body["reply"]
    ensure
      MemoAiChat.define_singleton_method(:new, original_new)
    end
  end

  test "create returns error when api key missing" do
    accounts(:one).update!(openai_api_key: nil)
    memo = memos(:one)

    post ai_chat_memo_url(memo),
      params: { messages: [ { role: "user", content: "hi" } ] },
      as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["error"], "API キー"
    assert body["settings_url"].present?
  end

  test "create forbidden for memo user cannot update" do
    other = memos(:two)
    other.update_columns(
      account_id: accounts(:two).id,
      visibility: Memo.visibilities[:public_everyone]
    )
    accounts(:one).update!(openai_api_key: "sk-test")

    post ai_chat_memo_url(other),
      params: { messages: [ { role: "user", content: "hi" } ] },
      as: :json

    assert_response :forbidden
  end

  test "edit page includes ai panel" do
    get edit_memo_url(memos(:one))
    assert_response :success
    assert_includes response.body, "memo-ai-panel"
    assert_includes response.body, "memo-ai-sidebar"
    assert_includes response.body, "AI アシスタント"
  end
end
