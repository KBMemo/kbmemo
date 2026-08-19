# frozen_string_literal: true

require "test_helper"

class MemoAiChatTest < ActiveSupport::TestCase
  def fake_client(reply: "== Reply", &capture)
    client = Object.new
    client.define_singleton_method(:chat) do |messages, **options|
      capture&.call(messages, options)
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
      existing_tags: [ "Ideas", "Work" ],
      local_client: local
    ).call

    assert_equal "== Reply", result[:reply]
    assert_equal :local, result[:backend]
    assert_equal :main, result[:model_role]
    assert_equal account.chat_server_model(:main), result[:model]
    assert_equal "system", captured.first[:role]
    assert_includes captured.first[:content], "AI Test Memo"
    assert_includes captured.first[:content], "Hello"
    assert_includes captured.first[:content], "ユーザーがエディタで選択"
    assert_includes captured.first[:content], "現在のタグ:"
    assert_includes captured.first[:content], "既存タグ一覧（利用頻度順）:"
    assert_includes captured.first[:content], "Ideas, Work"
    assert_includes captured.first[:content], "SNS向けのハッシュタグではなく"
  end

  test "call falls back to BYOK when local is unreachable" do
    account = accounts(:one)
    account.update!(openai_api_key: "sk-test")

    local = Object.new
    local.define_singleton_method(:chat) { |_m, **_k| raise Chat::LlmClient::ConnectionError, "refused" }
    captured_options = nil
    byok = fake_client(reply: "== BYOK reply") { |_messages, options| captured_options = options }

    result = MemoAiChat.new(
      account: account,
      memo: memos(:one),
      messages: [ { role: "user", content: "hi" } ],
      local_client: local,
      byok_client: byok
    ).call

    assert_equal "== BYOK reply", result[:reply]
    assert_equal({ "type" => "json_object" }, captured_options[:response_format])
    assert_equal :openai, result[:backend]
    assert_equal :main, result[:model_role]
    assert_equal MemoAiChat::OPENAI_MODEL, result[:model]
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
    local.define_singleton_method(:chat) { |_m, **_k| raise Chat::LlmClient::ConnectionError, "refused" }

    error = assert_raises(Chat::LlmClient::ConnectionError) do
      MemoAiChat.new(
        account: account, memo: memos(:one), messages: [], local_client: local
      ).call
    end
    assert_includes error.message, "API キー"
  end

  test "call uses an allowed selected model role" do
    result = MemoAiChat.new(
      account: accounts(:one),
      memo: memos(:one),
      messages: [ { role: "user", content: "hi" } ],
      model_role: :fast_chat,
      local_client: fake_client
    ).call

    assert_equal :fast_chat, result[:model_role]
    assert_equal accounts(:one).chat_server_model(:fast_chat), result[:model]
  end

  test "call parses JSON edits without forcing response_format on local llama-server" do
    payload = {
      "reply" => "表を更新しました",
      "edit" => { "target" => "unit", "content" => "|===\n| a | b\n|===" }
    }
    captured_options = nil
    local = fake_client(reply: payload.to_json) { |_messages, options| captured_options = options }

    result = MemoAiChat.new(
      account: accounts(:one),
      memo: memos(:one),
      messages: [ { role: "user", content: "列を足して" } ],
      local_client: local
    ).call

    assert_nil captured_options[:response_format]
    assert_equal "表を更新しました", result[:reply]
    assert_equal "unit", result[:edit][:target]
    assert_includes result[:edit][:content], "| a | b"
  end

  test "call treats non-JSON replies as chat-only" do
    result = MemoAiChat.new(
      account: accounts(:one),
      memo: memos(:one),
      messages: [ { role: "user", content: "hi" } ],
      local_client: fake_client(reply: "== Reply")
    ).call

    assert_equal "== Reply", result[:reply]
    assert_equal "none", result[:edit][:target]
    assert_equal "", result[:edit][:content]
  end

  test "call prefers live editor body and unit context" do
    captured = nil
    local = fake_client { |messages| captured = messages }

    MemoAiChat.new(
      account: accounts(:one),
      memo: memos(:one),
      messages: [ { role: "user", content: "整形して" } ],
      editor_context: {
        "body" => "LIVE BODY",
        "selection" => "BODY SEL",
        "active_unit" => { "kind" => "table", "adoc" => "|===\n| a\n|===" },
        "section" => { "heading" => "== Alpha", "adoc" => "== Alpha\nfoo" }
      },
      local_client: local
    ).call

    system_prompt = captured.first[:content]
    assert_includes system_prompt, "LIVE BODY"
    assert_includes system_prompt, "BODY SEL"
    assert_includes system_prompt, "カーソル位置のブロック種別: table"
    refute_includes system_prompt, "|===\n| a\n|==="
    assert_includes system_prompt, "カーソル位置の節見出し: == Alpha"
  end

  test "call ignores an unknown edit target" do
    result = MemoAiChat.new(
      account: accounts(:one),
      memo: memos(:one),
      messages: [ { role: "user", content: "hi" } ],
      local_client: fake_client(reply: { reply: "ok", edit: { target: "cells", content: "x" } }.to_json)
    ).call

    assert_equal "ok", result[:reply]
    assert_equal "none", result[:edit][:target]
    assert_equal "x", result[:edit][:content]
    assert_equal "x", result[:insert_content]
  end

  test "call extracts AsciiDoc insert_content from a JSON envelope" do
    payload = {
      "reply" => "追記しました",
      "edit" => { "target" => "none", "content" => "== Added\n\nBody" }
    }
    result = MemoAiChat.new(
      account: accounts(:one),
      memo: memos(:one),
      messages: [ { role: "user", content: "追記して" } ],
      local_client: fake_client(reply: payload.to_json)
    ).call

    assert_equal "追記しました", result[:reply]
    assert_equal "none", result[:edit][:target]
    assert_equal "== Added\n\nBody", result[:insert_content]
  end

  test "call unwraps a JSON dump so it is not used as the chat reply" do
    result = MemoAiChat.new(
      account: accounts(:one),
      memo: memos(:one),
      messages: [ { role: "user", content: "hi" } ],
      local_client: fake_client(reply: '{"reply":"","edit":{"target":"none","content":"* item"}}')
    ).call

    assert_equal "* item", result[:insert_content]
    refute_includes result[:reply], '{"reply"'
  end

  test "call converts markdown edit content to AsciiDoc" do
    payload = {
      "reply" => "節を書き換えました",
      "edit" => { "target" => "section", "content" => "## Hello\n\n- one\n- **two**" }
    }

    with_pandoc_unavailable do
      result = MemoAiChat.new(
        account: accounts(:one),
        memo: memos(:one),
        messages: [ { role: "user", content: "この節を直して" } ],
        local_client: fake_client(reply: payload.to_json)
      ).call

      assert_equal "section", result[:edit][:target]
      assert_equal "== Hello\n\n* one\n* *two*", result[:edit][:content]
      assert_equal "== Hello\n\n* one\n* *two*", result[:insert_content]
    end
  end

  test "asciidoc_from_text converts markdown headings lists and links" do
    markdown = "## Hello\n\n- first\n- **second**\n\n[Example](https://example.com)"

    with_pandoc_unavailable do
      assert_equal(
        "== Hello\n\n* first\n* *second*\n\nhttps://example.com[Example]",
        MemoAiChat.asciidoc_from_text(markdown)
      )
    end
  end

  test "asciidoc_from_text leaves AsciiDoc source unchanged" do
    adoc = "== Hello\n\n* first\n* *second*\n\n[source,ruby]\n----\nputs 1\n----"

    with_pandoc_unavailable do
      assert_equal adoc, MemoAiChat.asciidoc_from_text(adoc)
    end
  end

  test "initialize rejects an unknown model role" do
    assert_raises(ArgumentError) do
      MemoAiChat.new(
        account: accounts(:one),
        memo: memos(:one),
        messages: [],
        model_role: :arbitrary
      )
    end
  end

  def with_pandoc_unavailable
    PandocMarkdownToAsciidoc.stub(:convert, proc { raise PandocRunner::NotFound, "missing" }) do
      yield
    end
  end
end
