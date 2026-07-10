# frozen_string_literal: true

class NyoyMcpSettingsController < ApplicationController
  after_action :verify_authorized

  def show
    authorize :nyoy_mcp_settings, :show?
    @account = rodauth.rails_account
    @effective_url = Chat::NyoyMcpConfig.url(account: @account)
    @configured = Chat::NyoyMcpConfig.configured?(account: @account)
  end

  def update
    authorize :nyoy_mcp_settings, :update?
    @account = rodauth.rails_account

    if @account.update(nyoy_mcp_settings_params)
      redirect_to nyoy_mcp_path, notice: "Nyoy MCP 設定を保存しました。"
    else
      @effective_url = Chat::NyoyMcpConfig.url(account: @account)
      @configured = Chat::NyoyMcpConfig.configured?(account: @account)
      @using_fallback = @account.nyoy_mcp_url.blank? || !@account.nyoy_mcp_api_token_configured?
      render :show, status: :unprocessable_entity
    end
  end

  def test_connection
    authorize :nyoy_mcp_settings, :test_connection?

    account = rodauth.rails_account
    unless Chat::NyoyMcpConfig.configured?(account: account)
      render json: { ok: false, message: "URL と API トークンを保存してください。" }, status: :unprocessable_entity
      return
    end

    tools = Chat::NyoyMcpConfig.client(account: account).list_tools
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
