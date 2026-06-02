# frozen_string_literal: true

require "net/http"
require "json"

module Tsuzura
  class Client
    class << self
      def list_albums(owner_account_id:)
        uri = URI.join(api_base_url, "internal/albums")
        uri.query = URI.encode_www_form(owner_account_id: owner_account_id)
        request = Net::HTTP::Get.new(uri)
        request["X-Kbmemo-Internal-Secret"] = internal_secret.to_s
        response = http(uri).request(request)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue StandardError => e
        Rails.logger.warn("Tsuzura album list failed for account #{owner_account_id}: #{e.message}")
        nil
      end

      def fetch_album(ulid)
        normalized = ulid.to_s.strip.upcase
        return nil if normalized.blank?

        uri = URI.join(api_base_url, "/internal/albums/#{normalized}")
        request = Net::HTTP::Get.new(uri)
        request["X-Kbmemo-Internal-Secret"] = internal_secret.to_s
        response = http(uri).request(request)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue StandardError => e
        Rails.logger.warn("Tsuzura album fetch failed for #{normalized}: #{e.message}")
        nil
      end

      private

      def api_base_url
        ENV.fetch("TSUZURA_BASE_URL", "http://localhost:3008").chomp("/") + "/"
      end

      def internal_secret
        ENV["KBMEMO_TSUZURA_INTERNAL_SECRET"].presence ||
          Rails.application.credentials.dig(:tsuzura, :internal_secret).presence
      end

      def http(uri)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 5)
      end
    end
  end
end
