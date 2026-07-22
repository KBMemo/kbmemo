# frozen_string_literal: true

# == Schema Information
#
# Table name: agent_chat_conversations
#
#  id         :bigint           not null, primary key
#  title      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  memo_id    :bigint
#
# Indexes
#
#  index_agent_chat_conversations_on_account_id                 (account_id)
#  index_agent_chat_conversations_on_account_id_and_updated_at  (account_id,updated_at)
#  index_agent_chat_conversations_on_memo_id                    (memo_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (memo_id => memos.id)
#
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
