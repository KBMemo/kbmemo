# frozen_string_literal: true

class MemoAiChatsController < ApplicationController
  after_action :verify_authorized

  def create
    @memo = policy_scope(Memo).find(params[:id])
    authorize @memo, :ai_chat?

    result = MemoAiChat.new(
      account: rodauth.rails_account,
      memo: @memo,
      messages: chat_messages_param,
      selection: params[:selection],
      model_role: model_role_param,
      existing_tags: existing_tag_names
    ).call

    render json: result
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Chat::LlmClient::ConnectionError => e
    render json: { error: e.message, settings_url: chat_server_path }, status: :unprocessable_entity
  rescue Chat::LlmClient::Error => e
    render json: { error: e.message, settings_url: edit_profile_path }, status: :unprocessable_entity
  end

  private

  def model_role_param
    params[:model_role].presence || :main
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

  def existing_tag_names
    visible_memo_ids = policy_scope(Memo).select(:id)
    Tag.joins(:memo_tags)
      .where(memo_tags: { memo_id: visible_memo_ids })
      .group(:id)
      .order(Arel.sql("COUNT(memo_tags.id) DESC"), :name)
      .limit(MemoAiChat::MAX_EXISTING_TAGS)
      .pluck(:name)
  end
end
