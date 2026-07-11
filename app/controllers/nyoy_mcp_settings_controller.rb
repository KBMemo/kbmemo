# frozen_string_literal: true

class NyoyMcpSettingsController < ApplicationController
  after_action :verify_authorized

  def show
    authorize :nyoy_mcp_settings, :show?
    prepare_form
  end

  def update
    authorize :nyoy_mcp_settings, :update?
    @account = rodauth.rails_account

    if @account.update(nyoy_mcp_settings_params)
      redirect_to nyoy_mcp_path, notice: "Nyoy MCP 設定を保存しました。"
    else
      prepare_form
      render :show, status: :unprocessable_entity
    end
  end

  def test_connection
    authorize :nyoy_mcp_settings, :test_connection?

    account = rodauth.rails_account
    url, api_token = test_connection_credentials(account)
    if url.blank? || api_token.blank?
      render json: { ok: false, message: "MCP URL と API トークンを入力してください（トークン未入力時は保存済みトークンが必要です）。" },
             status: :unprocessable_entity
      return
    end

    tools = Chat::NyoyMcpClient.new(url: url, api_token: api_token).list_tools
    render json: {
      ok: true,
      message: "OK（#{tools.size} ツール）",
      tool_count: tools.size,
      tools: tools
    }
  rescue Chat::NyoyMcpClient::Error => e
    render json: { ok: false, message: e.message }, status: :unprocessable_entity
  end

  private

  def prepare_form
    @account = rodauth.rails_account
    @effective_url = Chat::NyoyMcpConfig.url(account: @account)
    @configured = Chat::NyoyMcpConfig.configured?(account: @account)
    @url_from_fallback = @account.nyoy_mcp_url.blank?
    @form_mcp_url = @account.nyoy_mcp_url.presence || @effective_url
  end

  def test_connection_credentials(account)
    overrides = test_connection_params
    url = overrides[:nyoy_mcp_url].presence || Chat::NyoyMcpConfig.url(account: account)
    api_token = overrides[:nyoy_mcp_api_token].presence || Chat::NyoyMcpConfig.api_token(account: account)
    [ url, api_token ]
  end

  def test_connection_params
    raw = params[:account]
    return {} if raw.blank?

    permitted = if raw.is_a?(ActionController::Parameters)
      raw.permit(:nyoy_mcp_url, :nyoy_mcp_api_token)
    else
      ActionController::Parameters.new(raw).permit(:nyoy_mcp_url, :nyoy_mcp_api_token)
    end

    url = permitted[:nyoy_mcp_url].to_s.strip.chomp("/")
    {
      nyoy_mcp_url: url.presence,
      nyoy_mcp_api_token: permitted[:nyoy_mcp_api_token].to_s.strip.presence
    }
  end

  def nyoy_mcp_settings_params
    permitted = params.require(:account).permit(:nyoy_mcp_url, :nyoy_mcp_api_token, :clear_nyoy_mcp_api_token)
    if ActiveModel::Type::Boolean.new.cast(permitted.delete(:clear_nyoy_mcp_api_token))
      permitted[:nyoy_mcp_api_token] = nil
    elsif permitted[:nyoy_mcp_api_token].blank?
      permitted.delete(:nyoy_mcp_api_token)
    end

    url = permitted[:nyoy_mcp_url].to_s.strip.chomp("/")
    permitted[:nyoy_mcp_url] = url.presence
    permitted
  end
end
