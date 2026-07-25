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
  test "as_ui_entry includes persisted user image attachments" do
    message = accounts(:one).agent_chat_conversations.create!.messages.create!(
      role: "user",
      content: "この画像は？",
      metadata: {
        "attachments" => [
          {
            "tsuzura_media_id" => "01JABCDEFGHJKMNPQRSTVWXYZ0",
            "filename" => "photo.jpg"
          }
        ]
      }
    )

    assert_equal(
      [
        {
          tsuzura_media_id: "01JABCDEFGHJKMNPQRSTVWXYZ0",
          filename: "photo.jpg"
        }
      ],
      message.as_ui_entry[:attachments]
    )
  end

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
    assert entry[:pending_tools]
  end

  test "as_ui_entry includes pending tool names when stored" do
    conversation = accounts(:one).agent_chat_conversations.create!
    message = conversation.messages.create!(
      role: "assistant",
      content: "回答",
      intent: "image_generation",
      model_role: "main",
      metadata: {
        "pending_tools" => true,
        "pending_tool_names" => [ "image_generation" ],
        "trace" => { "steps" => [] }
      }
    )

    entry = message.as_ui_entry
    assert entry[:pending_tools]
    assert_equal [ "image_generation" ], entry[:pending_tool_names]
  end

  test "as_ui_entry includes generated image urls when stored" do
    conversation = accounts(:one).agent_chat_conversations.create!
    message = conversation.messages.create!(
      role: "assistant",
      content: "できました",
      intent: "image_generation",
      model_role: "main",
      metadata: {
        "mcp" => { "image_urls" => [ "https://example.com/cat.png" ] },
        "trace" => { "steps" => [] }
      }
    )

    entry = message.as_ui_entry
    assert_equal [ "https://example.com/cat.png" ], entry[:generated_images]
  end

  test "as_ui_entry includes image generation watch when stored" do
    conversation = accounts(:one).agent_chat_conversations.create!
    message = conversation.messages.create!(
      role: "assistant",
      content: "生成中",
      intent: "image_generation",
      model_role: "main",
      metadata: {
        "mcp" => {
          "image_generation_watch" => { "id" => 42, "status" => "drafting" }
        },
        "trace" => { "steps" => [] }
      }
    )

    entry = message.as_ui_entry
    assert_equal({ "id" => 42, "status" => "drafting" }, entry[:image_generation_watch])
  end
end
