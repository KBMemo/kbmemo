# frozen_string_literal: true

require "test_helper"

class MemoAiChatTest < ActiveSupport::TestCase
  test "call delegates to OpenaiChatCompletion with system context" do
    account = accounts(:one)
    account.update!(openai_api_key: "sk-test")
    memo = memos(:one)
    memo.update_columns(title: "AI Test Memo", body: "= Intro\n\nHello")

    captured_messages = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:call) { |messages| captured_messages = messages; "== Reply" }

    original_new = OpenaiChatCompletion.method(:new)
    begin
      OpenaiChatCompletion.define_singleton_method(:new) { |**_kwargs| fake_client }

      result = MemoAiChat.new(
        account: account,
        memo: memo,
        messages: [ { role: "user", content: "続きを書いて" } ],
        selection: "Hello"
      ).call

      assert_equal({ reply: "== Reply" }, result)
      assert_equal "system", captured_messages.first[:role]
      assert_includes captured_messages.first[:content], "AI Test Memo"
      assert_includes captured_messages.first[:content], "Hello"
      assert_includes captured_messages.first[:content], "ユーザーがエディタで選択"
    ensure
      OpenaiChatCompletion.define_singleton_method(:new, original_new)
    end
  end

  test "call raises when api key missing" do
    account = accounts(:one)
    account.update!(openai_api_key: nil)

    assert_raises(OpenaiChatCompletion::Error) do
      MemoAiChat.new(account: account, memo: memos(:one), messages: []).call
    end
  end
end
