# frozen_string_literal: true

class ChatServersController < ApplicationController
  after_action :verify_authorized

  def show
    authorize :chat_server, :show?
    prepare_form
  end

  def update
    authorize :chat_server, :update?
    @account = rodauth.rails_account

    if @account.update_chat_server_settings!(settings_params)
      redirect_to chat_server_path, notice: "Chat サーバー設定を保存しました。"
    else
      prepare_form
      render :show, status: :unprocessable_entity
    end
  end

  def health_check
    authorize :chat_server, :health_check?

    results = Chat::ServerHealth.check_all(account: rodauth.rails_account)
    render json: {
      checks: results.map do |result|
        {
          role: result.role,
          base_url: result.base_url,
          ok: result.ok,
          message: result.message,
          model: result.model
        }
      end
    }
  end

  def list_models
    authorize :chat_server, :list_models?

    role = params[:role].to_s
    base_url = params[:base_url].to_s.strip.chomp("/")
    if base_url.blank?
      render json: { models: [], error: "接続 URL を入力してください。" }, status: :unprocessable_entity
      return
    end

    api_key = Rails.application.credentials.chat_models&.dig(:api_keys, role.to_sym)
    models = Chat::ServerModels.list_ids(base_url: base_url, api_key: api_key)
    if models.empty?
      render json: { models: [], error: "モデル一覧を取得できませんでした（/v1/models）。" }, status: :unprocessable_entity
      return
    end

    render json: { models: models }
  end

  private

  def prepare_form
    @account = rodauth.rails_account
    @settings = @account.chat_server_settings_payload
    @role_labels = Chat::ServerEndpoints::ROLE_LABELS
  end

  def settings_params
    raw = params.require(:chat_server_settings).permit(
      roles: Chat::ServerEndpoints::ROLES.index_with { %i[base_url model] }
    )

    { "roles" => (raw[:roles] || {}).to_h }
  end
end
