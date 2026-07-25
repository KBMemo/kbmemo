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

  test "append user message stores normalized image attachments" do
    conversation = @account.agent_chat_conversations.create!
    media_id = "01JABCDEFGHJKMNPQRSTVWXYZ0"

    @store.append_user_message!(
      conversation,
      content: "この画像は？",
      image_attachments: [
        {
          tsuzura_media_id: media_id.downcase,
          filename: "photo.jpg",
          preview_url: "blob:must-not-be-persisted"
        }
      ]
    )

    message = conversation.messages.last
    assert_equal(
      [ { "tsuzura_media_id" => media_id, "filename" => "photo.jpg" } ],
      message.metadata["attachments"]
    )
    assert_equal(
      [ { tsuzura_media_id: media_id, filename: "photo.jpg" } ],
      message.as_ui_entry[:attachments]
    )
  end

  test "replace memo references stores a bounded unique id list" do
    conversation = @account.agent_chat_conversations.create!
    references = [
      AgentChat::MemoReferences::Reference.new(id: memos(:one).id, title: "One", body: "", body_chars: 0),
      AgentChat::MemoReferences::Reference.new(id: memos(:one).id, title: "One", body: "", body_chars: 0),
      AgentChat::MemoReferences::Reference.new(id: memos(:two).id, title: "Two", body: "", body_chars: 0)
    ]

    @store.replace_memo_references!(conversation, references)

    assert_equal [ memos(:one).id, memos(:two).id ], conversation.reload.memo_reference_ids
  end

  test "clear destroys active conversation" do
    conversation = @account.agent_chat_conversations.create!
    conversation.messages.create!(role: "user", content: "hi", metadata: {})

    assert_difference -> { AgentChatConversation.count }, -1 do
      @store.clear!(conversation_id: conversation.id)
    end
  end

  test "merge_image_generation_result appends image urls to matching assistant message" do
    conversation = @account.agent_chat_conversations.create!
    message = conversation.messages.create!(
      role: "assistant",
      content: "ラフ案です",
      intent: "image_generation",
      model_role: "main",
      metadata: {
        "mcp" => {
          "image_urls" => [ "https://nyoy.example/draft.png" ],
          "image_generation_watch" => { "id" => 42, "status" => "awaiting_selection" }
        }
      }
    )

    updated = @store.merge_image_generation_result!(
      conversation_id: conversation.id,
      generation_id: 42,
      image_urls: [ "https://nyoy.example/final.png", "https://nyoy.example/draft.png" ],
      status: "completed",
      show_url: "https://nyoy.example/image_generations/42"
    )

    assert_equal message.id, updated.id
    message.reload
    assert_equal [
      "https://nyoy.example/final.png"
    ], message.metadata.dig("mcp", "image_urls")
    assert_equal "completed", message.metadata.dig("mcp", "image_generation_watch", "status")
    assert_equal "https://nyoy.example/image_generations/42",
      message.metadata.dig("mcp", "image_generation_watch", "show_url")
  end

  test "merge_image_generation_result persists status without image urls" do
    conversation = @account.agent_chat_conversations.create!
    message = conversation.messages.create!(
      role: "assistant",
      content: "ラフ案です",
      intent: "image_generation",
      model_role: "main",
      metadata: {
        "mcp" => {
          "image_urls" => [ "https://nyoy.example/draft.png" ],
          "image_generation_watch" => { "id" => 42, "status" => "awaiting_selection" }
        }
      }
    )

    updated = @store.merge_image_generation_result!(
      conversation_id: conversation.id,
      generation_id: 42,
      image_urls: [],
      status: "refining"
    )

    assert_equal message.id, updated.id
    message.reload
    assert_equal [ "https://nyoy.example/draft.png" ], message.metadata.dig("mcp", "image_urls")
    assert_equal "refining", message.metadata.dig("mcp", "image_generation_watch", "status")
  end

  test "list_recent returns conversations newest first" do
    older = @account.agent_chat_conversations.create!(title: "古い", updated_at: 2.days.ago)
    newer = @account.agent_chat_conversations.create!(title: "新しい", updated_at: 1.hour.ago)

    listed = @store.list_recent
    assert_equal [ newer.id, older.id ], listed.map(&:id)
  end

  test "conversation_for_show honors new chat flag" do
    @account.agent_chat_conversations.create!(title: "既存")

    assert_nil @store.conversation_for_show(conversation_id: nil, new_chat: true)
  end

  test "conversation_for_show loads explicit conversation id" do
    conversation = @account.agent_chat_conversations.create!(title: "指定")

    found = @store.conversation_for_show(conversation_id: conversation.id, new_chat: false)
    assert_equal conversation.id, found.id
  end
end
