# frozen_string_literal: true

module Chat
  # 徒然 in-app Agent が Nyoy MCP（HTTP）へ接続するための設定。
  module NyoyMcpConfig
    DEFAULT_URL = "https://nyoy.kbmemo.net/mcp"

    module_function

    def url(account: nil)
      account_url = account&.nyoy_mcp_url.to_s.strip.chomp("/")
      return account_url if account_url.present?

      ENV["NYOY_MCP_URL"].presence || credentials&.dig(:url).presence || DEFAULT_URL
    end

    def api_token(account: nil)
      account_token = account&.nyoy_mcp_api_token_decryptable? ? account.nyoy_mcp_api_token.to_s : ""
      normalize_api_token(
        account_token.presence || ENV["NYOY_MCP_API_TOKEN"].presence || credentials&.dig(:api_token)
      )
    end

    def normalize_api_token(value)
      token = value.to_s.strip.sub(/\ABearer\s+/i, "").strip
      token.presence
    end

    def configured?(account: nil)
      url(account: account).present? && api_token(account: account).present?
    end

    def client(account: nil)
      NyoyMcpClient.new(url: url(account: account), api_token: api_token(account: account))
    end

    def audio_client(account: nil)
      NyoyAudioClient.new(url: url(account: account), api_token: api_token(account: account))
    end

    def credentials
      Rails.application.credentials.nyoy_mcp
    rescue KeyError, ArgumentError
      nil
    end
  end
end
