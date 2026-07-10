# frozen_string_literal: true

class AgentChatsController < ApplicationController
  after_action :verify_authorized

  def show
    authorize :agent_chat, :show?

    store = conversation_store
    @conversation = store.active_conversation
    @initial_messages = store.ui_messages(@conversation)
    @conversation_id = @conversation&.id
  end

  def create
    authorize :agent_chat, :create?

    store = conversation_store
    conversation = store.find_or_create_conversation!(conversation_id: params[:conversation_id])
    user_text = last_user_text_from_params

    if user_text.blank?
      render json: { error: "メッセージが空です。" }, status: :unprocessable_entity
      return
    end

    store.append_user_message!(conversation, content: user_text)

    result = Chat::Agent.new.call(
      messages: chat_messages_param,
      account: rodauth.rails_account
    )

    if result.reply.blank?
      render json: { error: "応答を生成できませんでした。" }, status: :unprocessable_entity
      return
    end

    store.append_assistant_message!(conversation, result: result)

    render json: serialize_result(result, conversation: conversation)
  rescue Chat::LlmClient::Error => e
    render json: { error: e.message, settings_url: chat_server_path }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[AgentChatsController] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { error: "AI 処理中にエラーが発生しました。（#{e.message}）", settings_url: chat_server_path },
           status: :internal_server_error
  end

  def destroy
    authorize :agent_chat, :destroy?

    conversation_store.clear!(conversation_id: params[:conversation_id])
    head :no_content
  end

  private

  def conversation_store
    AgentChat::ConversationStore.new(account: rodauth.rails_account)
  end

  def serialize_result(result, conversation:)
    payload = {
      reply: result.reply,
      intent: result.intent,
      model_role: result.model_role,
      escalated: result.escalated,
      pending_tools: result.pending_tools,
      conversation_id: conversation.id
    }

    if result.rag
      payload[:rag] = {
        queries: result.rag.queries,
        hit_count: result.rag.hits.size,
        semantic_used: result.rag.semantic_used
      }
    end

    if result.mcp
      payload[:mcp] = {
        tools_run: result.mcp.tools_run.map(&:to_s),
        tools_skipped: result.mcp.tools_skipped.map(&:to_s),
        errors: result.mcp.errors
      }
    end

    payload
  end

  def chat_messages_param
    raw = params[:messages]
    return [] unless raw.is_a?(Array)

    raw.filter_map do |entry|
      next unless entry.is_a?(Hash) || entry.is_a?(ActionController::Parameters)

      h = entry.is_a?(ActionController::Parameters) ? entry : ActionController::Parameters.new(entry)
      h.permit(:role, :content).to_h.symbolize_keys.presence
    end
  end

  def last_user_text_from_params
    chat_messages_param.reverse_each do |entry|
      next unless entry[:role].to_s == "user"

      text = entry[:content].to_s.strip
      return text if text.present?
    end

    nil
  end
end
