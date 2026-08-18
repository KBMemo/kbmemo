# frozen_string_literal: true

require "test_helper"

class MemoAiChatsControllerTest < ActionDispatch::IntegrationTest
  test "create returns reply and backend" do
    memo = memos(:one)
    hidden_tag = Tag.create!(name: "PrivateTag")
    hidden_memo = Memo.create!(
      title: "Private memo",
      body: "secret",
      account: accounts(:two),
      memo_directory: memo_directories(:home_u_two),
      visibility: :owner_read_write
    )
    hidden_memo.tags << hidden_tag
    captured = nil

    fake = Object.new
    fake.define_singleton_method(:call) do
      {
        reply: "== AI section\n\nContent",
        backend: :local,
        model_role: :fast_chat,
        model: "fast-model"
      }
    end

    original_new = MemoAiChat.method(:new)
    begin
      MemoAiChat.define_singleton_method(:new) do |**kwargs|
        captured = kwargs
        fake
      end

      post ai_chat_memo_url(memo),
        params: {
          messages: [ { role: "user", content: "見出しを追加" } ],
          model_role: "fast_chat",
          editor_context: {
            body: "LIVE BODY",
            selection: "Hello",
            active_unit: { kind: "table", adoc: "|===" }
          }
        },
        as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "== AI section\n\nContent", body["reply"]
      assert_equal "local", body["backend"]
      assert_equal "fast-model", body["model"]
      assert_equal "fast_chat", captured[:model_role]
      assert_includes captured[:existing_tags], "Ideas"
      refute_includes captured[:existing_tags], "PrivateTag"
      assert_equal "LIVE BODY", captured[:editor_context]["body"]
      assert_equal "table", captured[:editor_context]["active_unit"]["kind"]
    ensure
      MemoAiChat.define_singleton_method(:new, original_new)
    end
  end

  test "create returns error when no backend is available" do
    memo = memos(:one)

    fake = Object.new
    fake.define_singleton_method(:call) { raise Chat::LlmClient::ConnectionError, "ローカル AI に接続できません。OpenAI API キーを登録してください。" }

    original_new = MemoAiChat.method(:new)
    begin
      MemoAiChat.define_singleton_method(:new) { |**_kwargs| fake }

      post ai_chat_memo_url(memo),
        params: { messages: [ { role: "user", content: "hi" } ] },
        as: :json

      assert_response :unprocessable_entity
      body = JSON.parse(response.body)
      assert_includes body["error"], "API キー"
      assert body["settings_url"].present?
    ensure
      MemoAiChat.define_singleton_method(:new, original_new)
    end
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

  test "create rejects an unsupported model role" do
    post ai_chat_memo_url(memos(:one)),
      params: {
        messages: [ { role: "user", content: "hi" } ],
        model_role: "arbitrary"
      },
      as: :json

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "未対応"
  end

  test "edit page includes ai panel" do
    get edit_memo_url(memos(:one))
    assert_response :success
    assert_includes response.body, "memo-ai-panel"
    assert_includes response.body, "memo-ai-sidebar"
    assert_includes response.body, "メモアシスト"
    assert_select "select#memo_ai_model_role[data-memo-ai-panel-target='modelRole']" do
      assert_select "option[value='main']", text: /Main.*gemma-4-e4b/
      assert_select "option[value='fast_chat']", text: /Fast chat.*gemma-4-e4b/
    end
    assert_select "[data-memo-ai-panel-target='messages'].hidden"
  end
end
