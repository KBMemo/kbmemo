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
class AgentChatMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze

  belongs_to :conversation,
             class_name: "AgentChatConversation",
             foreign_key: :agent_chat_conversation_id,
             inverse_of: :messages

  validates :role, presence: true, inclusion: { in: ROLES }

  scope :ordered, -> { order(:created_at, :id) }

  def assistant?
    role == "assistant"
  end

  def ui_meta
    return nil unless assistant?

    parts = []
    parts << "intent: #{intent}" if intent.present?
    if model_role.present?
      label = model_role.to_s
      label += " (escalated)" if metadata["escalated"]
      parts << "model: #{label}"
    end
    if metadata.dig("rag", "hit_count").to_i.positive?
      rag = "RAG: #{metadata.dig("rag", "hit_count")}件"
      rag += " · semantic" if metadata.dig("rag", "semantic_used")
      parts << rag
    end
    if metadata.dig("mcp", "tools_run")&.any?
      parts << "MCP: #{metadata.dig("mcp", "tools_run").join(", ")}"
    end
    parts << "tools: pending" if metadata["pending_tools"]
    parts.presence&.join(" · ")
  end

  def as_ui_entry
    entry = { role: role, content: content.to_s }
    if role == "user" && metadata["memo_references"].present?
      entry[:memo_references] = metadata["memo_references"]
    end
    if role == "user" && metadata["attachments"].present?
      entry[:attachments] = AgentChat::ImageAttachments.as_json(
        AgentChat::ImageAttachments.normalize(metadata["attachments"])
      )
    end
    if assistant?
      if metadata["trace"].present?
        entry[:activity] = metadata["trace"]
      else
        meta = ui_meta
        entry[:meta] = meta if meta.present?
      end
      if metadata["pending_tools"]
        entry[:pending_tools] = true
        entry[:pending_tool_names] = metadata["pending_tool_names"] if metadata["pending_tool_names"].present?
      end
      image_urls = metadata.dig("mcp", "image_urls")
      entry[:generated_images] = image_urls if image_urls.present?
      watch = metadata.dig("mcp", "image_generation_watch")
      entry[:image_generation_watch] = watch if watch.present?
      mcp_errors = metadata.dig("mcp", "errors")
      entry[:mcp_errors] = mcp_errors if mcp_errors.present?
    end
    entry
  end
end
