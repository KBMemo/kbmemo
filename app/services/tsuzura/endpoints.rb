# frozen_string_literal: true

module Tsuzura
  # Tsuzura API / 署名 URL の向き先。開発は localhost:3008 が既定（本番 API は ENV で明示）。
  module Endpoints
    DEV_DEFAULT = "http://localhost:3008"
    PRODUCTION_DEFAULT = "https://media.kbmemo.net"

    class << self
      def public_url
        resolve_url(
          env_key: "TSUZURA_PUBLIC_URL",
          credential_key: :public_url,
          production_default: PRODUCTION_DEFAULT
        )
      end

      def api_base_url
        "#{resolve_url(
          env_key: "TSUZURA_BASE_URL",
          credential_key: :base_url,
          production_default: PRODUCTION_DEFAULT
        )}/"
      end

      def web_manage_url
        public_url
      end

      private

      def resolve_url(env_key:, credential_key:, production_default:)
        explicit = ENV[env_key].presence
        return normalize(explicit) if explicit.present?

        return normalize(DEV_DEFAULT) if local_default?

        credential = Rails.application.credentials.dig(:tsuzura, credential_key).presence
        return normalize(credential) if credential.present?

        return normalize(production_default) if Rails.env.production?

        normalize(DEV_DEFAULT)
      end

      def local_default?
        Rails.env.development? || Rails.env.test?
      end

      def normalize(url)
        url.to_s.strip.chomp("/")
      end
    end
  end
end
