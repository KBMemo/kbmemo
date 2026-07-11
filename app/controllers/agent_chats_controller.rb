# frozen_string_literal: true

class AgentChatsController < ApplicationController
  after_action :verify_authorized

  def show
    authorize :agent_chat, :show?

    account = rodauth.rails_account
    store = conversation_store
    @conversations = store.list_recent
    @conversation = store.conversation_for_show(
      conversation_id: params[:conversation_id],
      new_chat: params[:new]
    )
    @new_chat = ActiveModel::Type::Boolean.new.cast(params[:new])
    @initial_messages = store.ui_messages(@conversation)
    @conversation_id = @conversation&.id
    @nyoy_mcp_configured = Chat::NyoyMcpConfig.configured?(account: account)
  end

  def nyoy_tools
    authorize :agent_chat, :nyoy_tools?

    account = rodauth.rails_account
    unless Chat::NyoyMcpConfig.configured?(account: account)
      render json: { tools: [], configured: false, error: "Nyoy MCP が未設定です。" }, status: :service_unavailable
      return
    end

    tools = Chat::NyoyMcpConfig.client(account: account).list_tools
    render json: { tools: tools, configured: true }
  rescue Chat::NyoyMcpClient::Error => e
    render json: { tools: [], configured: true, error: e.message }, status: :unprocessable_entity
  end

  def upload_image
    authorize :agent_chat, :upload_image?

    file = params[:file]
    if file.blank?
      render json: { error: "ファイルがありません。" }, status: :unprocessable_entity
      return
    end

    result = AgentChat::TsuzuraUpload.call(file: file, cookie_header: request.headers["Cookie"])
    render json: {
      tsuzura_media_id: result.tsuzura_media_id,
      filename: result.filename
    }
  rescue AgentChat::TsuzuraUpload::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    authorize :agent_chat, :create?

    store = conversation_store
    conversation = store.find_or_create_conversation!(conversation_id: params[:conversation_id])
    image_attachments = AgentChat::ImageAttachments.normalize(image_attachments_param)
    user_text = last_user_text_from_params
    user_text = "（画像を添付）" if user_text.blank? && image_attachments.any?
    turn_id = params[:turn_id].presence || SecureRandom.uuid
    account = rodauth.rails_account
    broadcaster = nil

    if user_text.blank?
      render json: { error: "メッセージが空です。" }, status: :unprocessable_entity
      return
    end

    broadcaster = AgentChat::UiBroadcaster.new(
      account: account,
      conversation: conversation,
      turn_id: turn_id
    )

    store.append_user_message!(conversation, content: user_text)

    result = Chat::Agent.new.call(
      messages: chat_messages_param,
      account: account,
      broadcaster: broadcaster,
      enabled_mcp_tools: enabled_mcp_tools_param,
      image_attachments: AgentChat::ImageAttachments.as_json(image_attachments),
      tsuzura_cookie_header: request.headers["Cookie"]
    )

    if result.reply.blank?
      broadcaster.turn_error(error: "応答を生成できませんでした。")
      render json: { error: "応答を生成できませんでした。" }, status: :unprocessable_entity
      return
    end

    store.append_assistant_message!(conversation, result: result)

    payload = serialize_result(result, conversation: conversation)
    broadcaster.turn_finalized(payload)
    render json: payload.merge(turn_id: turn_id)
  rescue Chat::LlmClient::Error => e
    broadcaster&.turn_error(error: e.message, settings_url: chat_server_path)
    render json: { error: e.message, settings_url: chat_server_path }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[AgentChatsController] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    broadcaster&.turn_error(
      error: "AI 処理中にエラーが発生しました。（#{e.message}）",
      settings_url: chat_server_path
    )
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

    if result.trace
      payload[:trace] = result.trace.as_json(
        account: rodauth.rails_account,
        intent: result.intent,
        model_role: result.model_role,
        escalated: result.escalated,
        interactions: result.interactions&.as_json
      )
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

  def enabled_mcp_tools_param
    raw = params[:enabled_mcp_tools]
    return nil if raw.nil?

    Array(raw).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def image_attachments_param
    top_level = params[:attachments] || params[:image_attachments]
    top = Array(top_level).reject { |entry| entry.blank? }
    return top if top.any?

    attachments_from_messages_param
  end

  def attachments_from_messages_param
    raw = params[:messages]
    return [] unless raw.is_a?(Array)

    raw.reverse_each do |entry|
      next unless entry.is_a?(Hash) || entry.is_a?(ActionController::Parameters)

      hash = entry.is_a?(ActionController::Parameters) ? entry.to_unsafe_h : entry
      next unless hash[:role].to_s == "user" || hash["role"].to_s == "user"

      attachments = hash[:attachments] || hash["attachments"]
      next if attachments.blank?

      return Array(attachments)
    end

    []
  end
end
