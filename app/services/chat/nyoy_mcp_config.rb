# frozen_string_literal: true

module Chat
  # 徒然 in-app Agent が Nyoy MCP（HTTP）へ接続するための設定。
  module NyoyMcpConfig
    DEFAULT_URL = "https://nyoy.kbmemo.net/mcp"

    module_function

    def url
      ENV["NYOY_MCP_URL"].presence || credentials&.dig(:url).presence || DEFAULT_URL
    end

    def api_token
      ENV["NYOY_MCP_API_TOKEN"].presence || credentials&.dig(:api_token).presence
    end

    def configured?
      url.present? && api_token.present?
    end

    def credentials
      Rails.application.credentials.nyoy_mcp
    rescue KeyError, ArgumentError
      nil
    end
  end
end
