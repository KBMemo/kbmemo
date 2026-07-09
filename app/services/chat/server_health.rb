# frozen_string_literal: true

require "net/http"
require "uri"

module Chat
  # llama-server の /health を叩いて到達性を確認する。
  class ServerHealth
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 5

    Result = Struct.new(:role, :base_url, :ok, :message, keyword_init: true)

    class << self
      # @param account [Account, nil]
      # @return [Array<Chat::ServerHealth::Result>]
      def check_all(account: nil)
        Chat::ServerEndpoints::ROLES.map do |role|
          config = Chat::ModelRegistry.for(role, account: account)
          check(role: role, base_url: config.base_url)
        rescue KeyError => e
          Result.new(role: role, base_url: nil, ok: false, message: e.message)
        end
      end

      def check(role:, base_url:)
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
          message: ok ? "OK (#{response.code})" : "HTTP #{response.code}"
        )
      rescue StandardError => e
        Result.new(role: role, base_url: base_url, ok: false, message: e.message)
      end

      private

      def health_uri(base_url)
        root = base_url.to_s.strip.chomp("/").delete_suffix("/v1")
        URI("#{root}/health")
      end
    end
  end
end
