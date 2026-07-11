# frozen_string_literal: true

require "test_helper"

class AgentChatConversationTest < ActiveSupport::TestCase
  test "display_title uses title when present" do
    conversation = accounts(:one).agent_chat_conversations.create!(title: "旅行メモ")
    assert_equal "旅行メモ", conversation.display_title
  end

  test "display_title falls back to first user message" do
    conversation = accounts(:one).agent_chat_conversations.create!
    conversation.messages.create!(role: "user", content: "RAG の設定を教えて", metadata: {})

    assert_equal "RAG の設定を教えて", conversation.display_title
  end
end
