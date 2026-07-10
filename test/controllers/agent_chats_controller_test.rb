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

  test "show restores persisted conversation messages" do
    conversation = accounts(:one).agent_chat_conversations.create!(title: "履歴")
    conversation.messages.create!(role: "user", content: "以前の質問", metadata: {})
    conversation.messages.create!(
      role: "assistant",
      content: "以前の回答",
      intent: "chat",
      model_role: "fast_chat",
      metadata: { "escalated" => false, "pending_tools" => false }
    )

    get agent_chat_url

    assert_response :success
    assert_includes response.body, "以前の質問"
    assert_includes response.body, "以前の回答"
    assert_includes response.body, "data-agent-chat-target=\"initialMessagesJson\""
    assert_includes response.body, "data-agent-chat-conversation-id-value=\"#{conversation.id}\""
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
      assert_predicate body["conversation_id"], :present?

      conversation = AgentChatConversation.find(body["conversation_id"])
      assert_equal 2, conversation.messages.count
      assert_equal "メモを探して", conversation.messages.ordered.first.content
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

  test "destroy clears persisted conversation" do
    conversation = accounts(:one).agent_chat_conversations.create!
    conversation.messages.create!(role: "user", content: "残す", metadata: {})

    assert_difference -> { AgentChatConversation.count }, -1 do
      delete agent_chat_url, params: { conversation_id: conversation.id }
    end

    assert_response :no_content
  end
end
