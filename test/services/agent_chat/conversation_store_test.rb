# frozen_string_literal: true

require "test_helper"

class AgentChatConversationStoreTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @store = AgentChat::ConversationStore.new(account: @account)
  end

  test "find_or_create_conversation creates a new row" do
    assert_difference -> { @account.agent_chat_conversations.count }, 1 do
      conversation = @store.find_or_create_conversation!
      assert conversation.persisted?
    end
  end

  test "find_or_create_conversation reuses owned conversation id" do
    existing = @account.agent_chat_conversations.create!(title: "既存")
    conversation = @store.find_or_create_conversation!(conversation_id: existing.id)
    assert_equal existing.id, conversation.id
  end

  test "append turn stores user and assistant messages with metadata" do
    conversation = @account.agent_chat_conversations.create!
    @store.append_user_message!(conversation, content: "メモを探して")
    result = Chat::Agent::Result.new(
      reply: "見つけました",
      intent: "rag_lookup",
      classification: nil,
      model_role: :main,
      escalated: true,
      tools: [ :rag_search ],
      pending_tools: false,
      rag: Chat::Tools::RagSearch::Result.new(
        queries: [ "q" ],
        hits: [ { title: "t" } ],
        context_text: "ctx",
        semantic_used: true
      )
    )
    @store.append_assistant_message!(conversation, result: result)

    conversation.reload
    assert_equal "メモを探して", conversation.title
    assert_equal 2, conversation.messages.count

    assistant = conversation.messages.ordered.last
    assert_equal "assistant", assistant.role
    assert_equal "rag_lookup", assistant.intent
    assert_equal "main", assistant.model_role
    assert assistant.metadata["escalated"]
    assert_equal 1, assistant.metadata.dig("rag", "hit_count")
    assert assistant.metadata.dig("rag", "semantic_used")
    assert_includes assistant.ui_meta, "RAG: 1件"
  end

  test "clear destroys active conversation" do
    conversation = @account.agent_chat_conversations.create!
    conversation.messages.create!(role: "user", content: "hi", metadata: {})

    assert_difference -> { AgentChatConversation.count }, -1 do
      @store.clear!(conversation_id: conversation.id)
    end
  end
end
