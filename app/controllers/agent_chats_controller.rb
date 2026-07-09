# frozen_string_literal: true

class AgentChatsController < ApplicationController
  after_action :verify_authorized

  def show
    authorize :agent_chat, :show?
  end

  def create
    authorize :agent_chat, :create?

    result = Chat::Agent.new.call(
      messages: chat_messages_param,
      account: rodauth.rails_account
    )

    if result.reply.blank?
      render json: { error: "応答を生成できませんでした。" }, status: :unprocessable_entity
      return
    end

    render json: serialize_result(result)
  rescue Chat::LlmClient::Error => e
    render json: { error: e.message, settings_url: chat_server_path }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[AgentChatsController] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { error: "AI 処理中にエラーが発生しました。（#{e.message}）", settings_url: chat_server_path },
           status: :internal_server_error
  end

  private

  def serialize_result(result)
    payload = {
      reply: result.reply,
      intent: result.intent,
      model_role: result.model_role,
      escalated: result.escalated,
      pending_tools: result.pending_tools
    }

    if result.rag
      payload[:rag] = {
        queries: result.rag.queries,
        hit_count: result.rag.hits.size,
        semantic_used: result.rag.semantic_used
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
end
