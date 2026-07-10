# frozen_string_literal: true

# == Schema Information
#
# Table name: agent_chat_messages
#
#  id                         :bigint           not null, primary key
#  content                    :text
#  intent                     :string
#  metadata                   :jsonb            not null
#  model_role                 :string
#  role                       :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  agent_chat_conversation_id :bigint           not null
#
# Indexes
#
#  idx_on_agent_chat_conversation_id_created_at_4dd7eae64b  (agent_chat_conversation_id,created_at)
#  index_agent_chat_messages_on_agent_chat_conversation_id  (agent_chat_conversation_id)
#  index_agent_chat_messages_on_role                        (role)
#
# Foreign Keys
#
#  fk_rails_...  (agent_chat_conversation_id => agent_chat_conversations.id)
#
require "test_helper"

class AgentChatMessageTest < ActiveSupport::TestCase
  test "as_ui_entry includes assistant meta" do
    conversation = accounts(:one).agent_chat_conversations.create!
    message = conversation.messages.create!(
      role: "assistant",
      content: "回答",
      intent: "chat",
      model_role: "fast_chat",
      metadata: { "escalated" => false, "pending_tools" => true }
    )

    entry = message.as_ui_entry
    assert_equal "assistant", entry[:role]
    assert_equal "回答", entry[:content]
    assert_includes entry[:meta], "intent: chat"
    assert_includes entry[:meta], "tools: pending"
  end
end
