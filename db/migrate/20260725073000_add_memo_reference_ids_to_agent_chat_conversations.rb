# frozen_string_literal: true

class AddMemoReferenceIdsToAgentChatConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_chat_conversations, :memo_reference_ids, :jsonb, null: false, default: []
  end
end
