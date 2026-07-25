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
    initial_reference_ids = if params[:memo_reference_id].present?
      [ params[:memo_reference_id] ]
    else
      @conversation&.memo_reference_ids
    end
    @initial_memo_references = AgentChat::MemoReferences.resolve(
      scope: policy_scope(Memo),
      ids: initial_reference_ids
    ).map(&:as_json)
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

  def memo_references
    authorize :agent_chat, :memo_references?

    query = params[:q].to_s.strip
    scope = policy_scope(Memo).order(updated_at: :desc)
    scope = scope.search_text(query) if query.present?
    memos = scope.limit(20)
    render json: {
      memos: memos.map do |memo|
        {
          id: memo.id,
          title: memo.title,
          body_chars: memo.body.to_s.length,
          updated_at: memo.updated_at.iso8601
        }
      end
    }
  end

  def update_memo_references
    authorize :agent_chat, :update_memo_references?

    conversation = conversation_store.find_conversation(params[:conversation_id])
    unless conversation
      render json: { error: "会話が見つかりません。" }, status: :not_found
      return
    end

    references = AgentChat::MemoReferences.resolve(
      scope: policy_scope(Memo),
      ids: params[:memo_reference_ids]
    )
    conversation_store.replace_memo_references!(conversation, references)
    render json: { memo_references: references.map(&:as_json) }
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

  def image_generation_status
    authorize :agent_chat, :image_generation_status?

    account = rodauth.rails_account
    unless Chat::NyoyMcpConfig.configured?(account: account)
      render json: { error: "Nyoy MCP が未設定です。" }, status: :service_unavailable
      return
    end

    client = Chat::NyoyMcpConfig.client(account: account)
    payload = client.call_tool(name: "get_image_generation", arguments: { id: image_generation_id_param })
    status = Chat::Tools::NyoyImageGenerationStatus.normalize(payload, client: client)
    persist_image_generation_result!(status)
    render json: status
  rescue Chat::NyoyMcpClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def refine_image_generation
    authorize :agent_chat, :refine_image_generation?

    account = rodauth.rails_account
    unless Chat::NyoyMcpConfig.configured?(account: account)
      render json: { error: "Nyoy MCP が未設定です。" }, status: :service_unavailable
      return
    end

    generation_id = image_generation_id_param
    draft_index = draft_index_param
    client = Chat::NyoyMcpConfig.client(account: account)
    payload = client.call_tool(
      name: "refine_image",
      arguments: { id: generation_id, draft_index: draft_index }
    )
    status_payload = status_payload_after_refine(client:, generation_id:, payload:)
    status = Chat::Tools::NyoyImageGenerationStatus.normalize(status_payload, client: client)
    persist_image_generation_result!(status)
    render json: status
  rescue Chat::NyoyMcpClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    authorize :agent_chat, :create?

    store = conversation_store
    conversation = store.find_or_create_conversation!(conversation_id: params[:conversation_id])
    image_attachments = AgentChat::ImageAttachments.normalize(image_attachments_param)
    requested_reference_ids = if params.key?(:memo_reference_ids)
      params[:memo_reference_ids]
    else
      conversation.memo_reference_ids
    end
    memo_references = AgentChat::MemoReferences.resolve(
      scope: policy_scope(Memo),
      ids: requested_reference_ids
    )
    store.replace_memo_references!(conversation, memo_references)
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

    store.append_user_message!(
      conversation,
      content: user_text,
      memo_references: memo_references.map(&:as_json)
    )

    if (refine_request = natural_language_refine_request(conversation:, user_text: user_text))
      payload = handle_natural_language_refine!(
        conversation: conversation,
        account: account,
        refine_request: refine_request,
        turn_id: turn_id,
        broadcaster: broadcaster
      )
      render json: payload
      return
    end

    result = Chat::Agent.new.call(
      messages: chat_messages_param,
      account: account,
      broadcaster: broadcaster,
      enabled_mcp_tools: enabled_mcp_tools_param,
      image_attachments: AgentChat::ImageAttachments.as_json(image_attachments),
      memo_references: memo_references,
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
  rescue Chat::NyoyMcpClient::Error => e
    broadcaster&.turn_error(error: e.message, settings_url: nyoy_mcp_path)
    render json: { error: e.message, settings_url: nyoy_mcp_path }, status: :unprocessable_entity
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
      pending_tool_names: Array(result.pending_tool_names).map(&:to_s),
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
          errors: result.mcp.errors,
          image_urls: Array(result.mcp.image_urls).map(&:to_s).reject(&:blank?),
          image_generation_watch: result.mcp.image_generation_watch
        }.compact
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

  def image_generation_id_param
    generation_id = params[:id].to_i
    raise ArgumentError, "画像生成 ID が不正です。" if generation_id <= 0

    generation_id
  end

  def draft_index_param
    raise ArgumentError, "draft_index は 0 から 3 の範囲で指定してください。" if params[:draft_index].nil?

    draft_index = params[:draft_index].to_i
    raise ArgumentError, "draft_index は 0 から 3 の範囲で指定してください。" unless draft_index.between?(0, 3)

    draft_index
  end

  def status_payload_after_refine(client:, generation_id:, payload:)
    return payload if payload.is_a?(Hash) && payload["status"].present?

    client.call_tool(name: "get_image_generation", arguments: { id: generation_id })
  end

  def natural_language_refine_request(conversation:, user_text:)
    draft_index = natural_language_draft_index(user_text)
    return nil if draft_index.nil?

    message = latest_refinable_image_generation_message(conversation)
    return nil unless message

    watch = message.metadata.dig("mcp", "image_generation_watch")
    generation_id = watch["id"].presence
    return nil if generation_id.blank?

    { generation_id: generation_id.to_i, draft_index: draft_index }
  end

  def natural_language_draft_index(text)
    normalized = text.to_s.strip.tr("０-９", "0-9")
    return nil if normalized.blank?

    number =
      if (match = normalized.match(/(?:^|[^\d])([1-4])\s*(?:番|枚目|つ目|個目|案|draft|ドラフト)/i))
        match[1].to_i
      elsif (match = normalized.match(/(?:^|[^\d])(?:draft|ドラフト)\s*([1-4])(?:[^\d]|$)/i))
        match[1].to_i
      elsif normalized.match?(/\A[1-4]\z/)
        normalized.to_i
      end

    return nil unless number

    number - 1
  end

  def latest_refinable_image_generation_message(conversation)
    conversation.messages.ordered.reverse_order.find do |candidate|
      next false unless candidate.assistant?

      watch = candidate.metadata.dig("mcp", "image_generation_watch")
      watch.is_a?(Hash) && watch["id"].present? && watch["status"].to_s == "awaiting_selection"
    end
  end

  def handle_natural_language_refine!(conversation:, account:, refine_request:, turn_id:, broadcaster:)
    unless Chat::NyoyMcpConfig.configured?(account: account)
      raise Chat::NyoyMcpClient::NotConfiguredError, "Nyoy MCP が未設定です。"
    end

    generation_id = refine_request.fetch(:generation_id)
    draft_index = refine_request.fetch(:draft_index)
    client = Chat::NyoyMcpConfig.client(account: account)
    payload = client.call_tool(
      name: "refine_image",
      arguments: { id: generation_id, draft_index: draft_index }
    )
    status_payload = status_payload_after_refine(client:, generation_id:, payload:)
    status = Chat::Tools::NyoyImageGenerationStatus.normalize(status_payload, client: client)
    persist_image_generation_status!(conversation: conversation, status: status)

    reply = "#{draft_index + 1}番の仕上げを開始しました。"
    conversation.messages.create!(
      role: "assistant",
      content: reply,
      intent: "image_generation",
      model_role: "nyoy_mcp",
      metadata: {
        "escalated" => false,
        "pending_tools" => false,
        "pending_tool_names" => [],
        "tools" => [ "refine_image" ],
        "mcp" => {
          "tools_run" => [ "refine_image" ],
          "tools_skipped" => [],
          "errors" => [],
          "image_urls" => Array(status[:image_urls]).map(&:to_s).reject(&:blank?),
          "image_generation_watch" => status.slice(:id, :status, :show_url).compact
        }
      }
    )
    conversation.touch

    result_payload = {
      reply: reply,
      intent: "image_generation",
      model_role: "nyoy_mcp",
      escalated: false,
      pending_tools: false,
      pending_tool_names: [],
      conversation_id: conversation.id,
      mcp: {
        tools_run: [ "refine_image" ],
        tools_skipped: [],
        errors: [],
        image_urls: Array(status[:image_urls]).map(&:to_s).reject(&:blank?),
        image_generation_watch: status.slice(:id, :status, :show_url).compact
      },
      turn_id: turn_id
    }
    broadcaster.turn_finalized(result_payload)
    result_payload
  end

  def persist_image_generation_result!(status)
    return if params[:conversation_id].blank?

    conversation_store.merge_image_generation_result!(
      conversation_id: params[:conversation_id],
      generation_id: status[:id] || params[:id],
      image_urls: status[:image_urls],
      status: status[:status],
      show_url: status[:show_url]
    )
  end

  def persist_image_generation_status!(conversation:, status:)
    conversation_store.merge_image_generation_result!(
      conversation_id: conversation.id,
      generation_id: status[:id],
      image_urls: status[:image_urls],
      status: status[:status],
      show_url: status[:show_url]
    )
  end
end
