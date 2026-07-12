# frozen_string_literal: true

module AgentChat
  # Persists in-app Agent Chat turns per account (Phase 8).
  class ConversationStore
    def initialize(account:)
      @account = account
    end

    def active_conversation
      @account.agent_chat_conversations.recent_first.first
    end

    def list_recent(limit: 40)
      @account.agent_chat_conversations.recent_first.limit(limit)
    end

    def conversation_for_show(conversation_id:, new_chat:)
      return nil if ActiveModel::Type::Boolean.new.cast(new_chat)

      conversation = find_conversation(conversation_id)
      return conversation if conversation_id.present?

      active_conversation
    end

    def find_conversation(conversation_id)
      return nil if conversation_id.blank?

      @account.agent_chat_conversations.find_by(id: conversation_id)
    end

    def find_or_create_conversation!(conversation_id: nil)
      conversation = find_conversation(conversation_id)
      return conversation if conversation

      @account.agent_chat_conversations.create!
    end

    def ui_messages(conversation)
      return [] unless conversation

      conversation.messages.ordered.map(&:as_ui_entry)
    end

    def append_user_message!(conversation, content:)
      conversation.messages.create!(role: "user", content: content, metadata: {})
      conversation.assign_title_from!(content)
      conversation.touch
      conversation
    end

    def append_assistant_message!(conversation, result:)
      conversation.messages.create!(
        role: "assistant",
        content: result.reply,
        intent: result.intent,
        model_role: result.model_role&.to_s,
        metadata: assistant_metadata(result)
      )
      conversation.touch
      conversation
    end

    def clear!(conversation_id: nil)
      conversation = find_conversation(conversation_id) || active_conversation
      conversation&.destroy
    end

    private

    def assistant_metadata(result)
      metadata = {
        "escalated" => result.escalated,
        "pending_tools" => result.pending_tools,
        "pending_tool_names" => Array(result.pending_tool_names).map(&:to_s),
        "tools" => Array(result.tools).map(&:to_s)
      }

      if result.rag
        metadata["rag"] = {
          "queries" => result.rag.queries,
          "hit_count" => result.rag.hits.size,
          "semantic_used" => result.rag.semantic_used
        }
      end

      if result.mcp
        metadata["mcp"] = {
          "tools_run" => Array(result.mcp.tools_run).map(&:to_s),
          "tools_skipped" => Array(result.mcp.tools_skipped).map(&:to_s),
          "errors" => result.mcp.errors,
          "image_urls" => Array(result.mcp.image_urls).map(&:to_s).reject(&:blank?),
          "image_generation_watch" => result.mcp.image_generation_watch
        }.compact
      end

      if result.trace
        metadata["trace"] = result.trace.as_json(
          account: @account,
          intent: result.intent,
          model_role: result.model_role,
          escalated: result.escalated,
          interactions: result.interactions&.as_json
        )
      end

      metadata
    end
  end
end
