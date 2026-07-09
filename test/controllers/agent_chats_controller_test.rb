# frozen_string_literal: true

require "test_helper"

class AgentChatsControllerTest < ActionDispatch::IntegrationTest
  test "show requires authentication" do
    sign_out
    get agent_chat_url
    assert_match %r{/login}, @response.redirect_url
  end

  test "show renders chat page when logged in" do
    get agent_chat_url
    assert_response :success
    assert_includes response.body, "agent-chat"
    assert_includes response.body, "AI チャット"
  end

  test "create returns agent reply json" do
    fake_result = Chat::Agent::Result.new(
      reply: "回答です",
      intent: "rag_lookup",
      classification: nil,
      model_role: :main,
      escalated: false,
      tools: [ :rag_search ],
      pending_tools: false,
      rag: Chat::Tools::RagSearch::Result.new(
        queries: [ "q" ],
        hits: [],
        context_text: "",
        semantic_used: false
      )
    )

    original_new = Chat::Agent.method(:new)
    begin
      Chat::Agent.define_singleton_method(:new) { |**_kwargs| Object.new.tap { |o| o.define_singleton_method(:call) { |**_| fake_result } } }

      post agent_chat_url,
        params: { messages: [ { role: "user", content: "メモを探して" } ] },
        as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "回答です", body["reply"]
      assert_equal "rag_lookup", body["intent"]
      assert_equal "main", body["model_role"]
      assert_equal false, body["escalated"]
      assert_equal 0, body.dig("rag", "hit_count")
    ensure
      Chat::Agent.define_singleton_method(:new, original_new)
    end
  end

  test "create returns error when reply blank" do
    fake_result = Chat::Agent::Result.new(
      reply: nil, intent: "unknown", classification: nil,
      model_role: nil, escalated: false, tools: [], pending_tools: false, rag: nil
    )

    original_new = Chat::Agent.method(:new)
    begin
      Chat::Agent.define_singleton_method(:new) { |**_kwargs| Object.new.tap { |o| o.define_singleton_method(:call) { |**_| fake_result } } }

      post agent_chat_url, params: { messages: [ { role: "user", content: "?" } ] }, as: :json

      assert_response :unprocessable_entity
      assert_includes JSON.parse(response.body)["error"], "応答"
    ensure
      Chat::Agent.define_singleton_method(:new, original_new)
    end
  end

  test "create returns llm error as json" do
    original_new = Chat::Agent.method(:new)
    begin
      Chat::Agent.define_singleton_method(:new) do |**_kwargs|
        Object.new.tap do |o|
          o.define_singleton_method(:call) { |**_| raise Chat::LlmClient::Error, "down" }
        end
      end

      post agent_chat_url, params: { messages: [ { role: "user", content: "hi" } ] }, as: :json

      assert_response :unprocessable_entity
      assert_equal "down", JSON.parse(response.body)["error"]
    ensure
      Chat::Agent.define_singleton_method(:new, original_new)
    end
  end
end
