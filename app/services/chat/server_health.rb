# frozen_string_literal: true

require "net/http"
require "uri"

module Chat
  # llama-server の /health を叩いて到達性を確認する。
  class ServerHealth
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 5

    Result = Struct.new(:role, :base_url, :ok, :message, :model, keyword_init: true)

    class << self
      # @param account [Account, nil]
      # @param role_overrides [Hash, nil] フォーム入力（"roles" => { "intent" => { "base_url" => ..., "model" => ... } }）
      # @return [Array<Chat::ServerHealth::Result>]
      def check_all(account: nil, role_overrides: nil)
        overrides = normalize_role_overrides(role_overrides)

        Chat::ServerEndpoints::ROLES.map do |role|
          base_url, model = resolve_role_config(role, account: account, overrides: overrides)
          if base_url.blank?
            next Result.new(
              role: role,
              base_url: nil,
              ok: false,
              message: "未設定",
              model: model
            )
          end

          api_key = resolve_api_key(role)
          check(
            role: role,
            base_url: base_url,
            api_key: api_key,
            model: model
          )
        rescue KeyError => e
          Result.new(role: role, base_url: nil, ok: false, message: e.message, model: nil)
        end
      end

      def check(role:, base_url:, api_key: nil, model: nil)
        uri = health_uri(base_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        response = http.get(uri.request_uri)
        ok = response.is_a?(Net::HTTPSuccess)
        Result.new(
          role: role,
          base_url: base_url,
          ok: ok,
          message: ok ? "OK (#{response.code})" : "HTTP #{response.code}",
          model: model
        )
      rescue StandardError => e
        Result.new(role: role, base_url: base_url, ok: false, message: e.message, model: model)
      end

      private

      def normalize_role_overrides(role_overrides)
        return nil if role_overrides.blank?

        roles = role_overrides.is_a?(Hash) ? role_overrides["roles"] || role_overrides[:roles] : nil
        return nil unless roles.is_a?(Hash)

        roles.transform_keys(&:to_s).transform_values do |entry|
          next {} unless entry.is_a?(Hash)

          entry.stringify_keys.slice("base_url", "model")
        end
      end

      def resolve_role_config(role, account:, overrides:)
        role_key = role.to_s
        if overrides&.key?(role_key)
          entry = overrides[role_key] || {}
          base_url = entry["base_url"].to_s.strip.chomp("/").presence
          model = entry["model"].to_s.strip.presence
          return [ base_url, model ]
        end

        [
          account&.chat_server_base_url(role),
          account&.chat_server_model(role)
        ]
      end

      def resolve_api_key(role)
        Chat::ModelRegistry.for(role, account: nil).api_key
      rescue KeyError
        Rails.application.credentials.chat_models&.dig(:api_keys, role.to_sym)
      end

      def health_uri(base_url)
        root = base_url.to_s.strip.chomp("/").delete_suffix("/v1")
        URI("#{root}/health")
      end
    end
  end
end
