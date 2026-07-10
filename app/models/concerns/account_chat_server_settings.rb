# frozen_string_literal: true

module AccountChatServerSettings
  extend ActiveSupport::Concern

  class_methods do
    def normalize_chat_server_settings(raw)
      data = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
      roles = {}

      if data["roles"].is_a?(Hash)
        data["roles"].each do |role_key, config|
          next unless Chat::ServerEndpoints::ROLES.map(&:to_s).include?(role_key.to_s)

          normalized = normalize_role_config(config)
          roles[role_key.to_s] = normalized if normalized.present?
        end
      end

      legacy_urls = data["base_urls"].is_a?(Hash) ? data["base_urls"] : {}
      legacy_models = data["models"].is_a?(Hash) ? data["models"] : {}
      Chat::ServerEndpoints::ROLES.each do |role|
        role_key = role.to_s
        url = legacy_urls[role_key].to_s.strip.chomp("/")
        model = legacy_models[role_key].to_s.strip
        next if url.blank? && model.blank?

        roles[role_key] ||= {}
        roles[role_key]["base_url"] = url if url.present?
        roles[role_key]["model"] = model if model.present?
      end

      { "roles" => roles }
    end

    def normalize_role_config(config)
      entry = config.is_a?(Hash) ? config.deep_stringify_keys : {}
      url = entry["base_url"].to_s.strip.chomp("/")
      model = entry["model"].to_s.strip

      normalized = {}
      normalized["base_url"] = url if url.present?
      normalized["model"] = model if model.present?
      normalized
    end
  end

  def chat_server_settings_payload
    self.class.normalize_chat_server_settings(chat_server_settings)
  end

  def chat_server_role_settings(role)
    chat_server_settings_payload.dig("roles", role.to_s) || {}
  end

  # @param role [Symbol, String]
  # @return [String, nil]
  def chat_server_base_url(role)
    chat_server_role_settings(role)["base_url"].presence
  end

  # @param role [Symbol, String]
  # @return [String, nil]
  def chat_server_model(role)
    chat_server_role_settings(role)["model"].presence
  end

  def update_chat_server_settings!(payload)
    update!(chat_server_settings: self.class.normalize_chat_server_settings(payload))
  end
end
