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
          message: result.message
        }
      end
    }
  end

  private

  def prepare_form
    @account = rodauth.rails_account
    @settings = @account.chat_server_settings_payload
    @default_urls = Chat::ServerEndpoints.default_urls
    @role_urls = Chat::ServerEndpoints.resolved_urls(account: @account)
    @role_labels = Chat::ServerEndpoints::ROLE_LABELS
    @default_ports = Chat::ServerEndpoints::DEFAULT_PORTS
    @models_config = Rails.application.config_for(:chat_models).to_h
  end

  def settings_params
    raw = params.require(:chat_server_settings).permit(
      base_urls: Chat::ServerEndpoints::ROLES.map(&:to_s)
    )

    { "base_urls" => (raw[:base_urls] || {}).to_h.compact_blank }
  end
end
