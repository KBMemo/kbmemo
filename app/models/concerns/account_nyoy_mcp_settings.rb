# frozen_string_literal: true

module AccountNyoyMcpSettings
  extend ActiveSupport::Concern

  included do
    encrypts :nyoy_mcp_api_token
  end

  def nyoy_mcp_api_token_configured?
    nyoy_mcp_api_token.present?
  end

  def nyoy_mcp_configured?
    nyoy_mcp_url.present? && nyoy_mcp_api_token_configured?
  end
end
