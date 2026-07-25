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

    def append_user_message!(conversation, content:, memo_references: [], image_attachments: [])
      metadata = {}
      metadata["memo_references"] = memo_references if memo_references.present?
      attachments = AgentChat::ImageAttachments.as_json(
        AgentChat::ImageAttachments.normalize(image_attachments)
      )
      metadata["attachments"] = attachments if attachments.present?
      conversation.messages.create!(role: "user", content: content, metadata: metadata)
      conversation.assign_title_from!(content)
      conversation.touch
      conversation
    end

    def replace_memo_references!(conversation, references)
      ids = Array(references).filter_map { |reference| reference.respond_to?(:id) ? reference.id : nil }
      conversation.update!(memo_reference_ids: ids.uniq.first(AgentChat::MemoReferences::MAX_COUNT))
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

    def merge_image_generation_result!(conversation_id:, generation_id:, image_urls:, status: nil, show_url: nil)
      urls = Array(image_urls).map(&:to_s).reject(&:blank?)
      return nil if generation_id.blank?

      conversation = find_conversation(conversation_id)
      return nil unless conversation

      message = conversation.messages.ordered.reverse_order.find do |candidate|
        candidate.assistant? &&
          candidate.metadata.dig("mcp", "image_generation_watch", "id").to_s == generation_id.to_s
      end
      return nil unless message

      metadata = message.metadata.deep_dup
      metadata["mcp"] ||= {}
      existing_status = metadata.dig("mcp", "image_generation_watch", "status").to_s
      replace_drafts = existing_status == "awaiting_selection" && status.to_s != "awaiting_selection"
      if urls.any?
        previous_urls = Array(metadata.dig("mcp", "image_urls")).map(&:to_s)
        existing_urls = replace_drafts ? [] : previous_urls
        incoming_urls = replace_drafts ? urls - previous_urls : urls
        metadata["mcp"]["image_urls"] = (existing_urls + incoming_urls).reject(&:blank?).uniq
      end
      metadata["mcp"]["image_generation_watch"] ||= {}
      metadata["mcp"]["image_generation_watch"]["id"] = generation_id
      metadata["mcp"]["image_generation_watch"]["status"] = status if status.present?
      metadata["mcp"]["image_generation_watch"]["show_url"] = show_url if show_url.present?

      message.update!(metadata: metadata)
      conversation.touch
      message
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
