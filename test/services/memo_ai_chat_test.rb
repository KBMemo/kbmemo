# frozen_string_literal: true

require "test_helper"

class MemoAiChatTest < ActiveSupport::TestCase
  def fake_client(reply: "== Reply", &capture)
    client = Object.new
    client.define_singleton_method(:chat) do |messages|
      capture&.call(messages)
      reply
    end
    client
  end

  test "call uses the local backend and includes memo context" do
    account = accounts(:one)
    memo = memos(:one)
    memo.update_columns(title: "AI Test Memo", body: "= Intro\n\nHello")

    captured = nil
    local = fake_client { |messages| captured = messages }

    result = MemoAiChat.new(
      account: account,
      memo: memo,
      messages: [ { role: "user", content: "続きを書いて" } ],
      selection: "Hello",
      local_client: local
    ).call

    assert_equal({ reply: "== Reply", backend: :local }, result)
    assert_equal "system", captured.first[:role]
    assert_includes captured.first[:content], "AI Test Memo"
    assert_includes captured.first[:content], "Hello"
    assert_includes captured.first[:content], "ユーザーがエディタで選択"
  end

  test "call falls back to BYOK when local is unreachable" do
    account = accounts(:one)
    account.update!(openai_api_key: "sk-test")

    local = Object.new
    local.define_singleton_method(:chat) { |_m| raise Chat::LlmClient::ConnectionError, "refused" }
    byok = fake_client(reply: "== BYOK reply")

    result = MemoAiChat.new(
      account: account,
      memo: memos(:one),
      messages: [ { role: "user", content: "hi" } ],
      local_client: local,
      byok_client: byok
    ).call

    assert_equal({ reply: "== BYOK reply", backend: :openai }, result)
  end

  test "call falls back to BYOK when local registry is misconfigured" do
    account = accounts(:one)
    account.update!(openai_api_key: "sk-test")
    byok = fake_client(reply: "== BYOK reply")

    Chat::ModelRegistry.stub(:for, ->(*) { raise KeyError, "base_url 未設定" }) do
      result = MemoAiChat.new(
        account: account,
        memo: memos(:one),
        messages: [ { role: "user", content: "hi" } ],
        byok_client: byok
      ).call

      assert_equal :openai, result[:backend]
    end
  end

  test "call raises when local unreachable and no BYOK key" do
    account = accounts(:one)
    account.update!(openai_api_key: nil)

    local = Object.new
    local.define_singleton_method(:chat) { |_m| raise Chat::LlmClient::ConnectionError, "refused" }

    error = assert_raises(Chat::LlmClient::ConnectionError) do
      MemoAiChat.new(
        account: account, memo: memos(:one), messages: [], local_client: local
      ).call
    end
    assert_includes error.message, "API キー"
  end
end
