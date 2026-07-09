# frozen_string_literal: true

module AccountChatServerSettings
  extend ActiveSupport::Concern

  class_methods do
    def normalize_chat_server_settings(raw)
      data = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
      base_urls = data["base_urls"].is_a?(Hash) ? data["base_urls"] : {}

      normalized_urls = {}
      Chat::ServerEndpoints::ROLES.each do |role|
        url = base_urls[role.to_s].to_s.strip.chomp("/")
        normalized_urls[role.to_s] = url if url.present?
      end

      { "base_urls" => normalized_urls }
    end
  end

  def chat_server_settings_payload
    self.class.normalize_chat_server_settings(chat_server_settings)
  end

  # @param role [Symbol, String]
  # @return [String, nil] 明示設定のみ。未設定なら nil（ModelRegistry が環境既定へフォールバック）。
  def chat_server_base_url(role)
    chat_server_settings_payload.dig("base_urls", role.to_s).presence
  end

  def update_chat_server_settings!(payload)
    update!(chat_server_settings: self.class.normalize_chat_server_settings(payload))
  end
end
