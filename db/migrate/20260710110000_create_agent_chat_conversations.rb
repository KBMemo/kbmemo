# frozen_string_literal: true

class CreateAgentChatConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_chat_conversations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :memo, foreign_key: true
      t.string :title

      t.timestamps
    end

    add_index :agent_chat_conversations, %i[account_id updated_at]

    create_table :agent_chat_messages do |t|
      t.references :agent_chat_conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content
      t.string :intent
      t.string :model_role
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :agent_chat_messages, %i[agent_chat_conversation_id created_at]
    add_index :agent_chat_messages, :role
  end
end
