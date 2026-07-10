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
      # @return [Array<Chat::ServerHealth::Result>]
      def check_all(account: nil)
        Chat::ServerEndpoints::ROLES.map do |role|
          base_url = account&.chat_server_base_url(role)
          model = account&.chat_server_model(role)
          if base_url.blank?
            next Result.new(
              role: role,
              base_url: nil,
              ok: false,
              message: "未設定",
              model: model
            )
          end

          config = Chat::ModelRegistry.for(role, account: account)
          check(
            role: role,
            base_url: base_url,
            api_key: config.api_key,
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

      def health_uri(base_url)
        root = base_url.to_s.strip.chomp("/").delete_suffix("/v1")
        URI("#{root}/health")
      end
    end
  end
end
