# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "uri"

module Chat
  # llama-server 等 OpenAI 互換 API の /v1/models からモデル ID 一覧を取得する。
  class ServerModels
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 5
    CACHE_TTL = 5.minutes

    class << self
      # @param base_url [String]
      # @param api_key [String, nil]
      # @return [Array<String>]
      def list_ids(base_url:, api_key: nil)
        url = base_url.to_s.strip
        return [] if url.blank?

        cache_key = cache_key_for(url, api_key, suffix: "list")
        cached = Rails.cache.read(cache_key)
        return cached if cached.is_a?(Array)

        ids = fetch_ids(base_url: url, api_key: api_key)
        Rails.cache.write(cache_key, ids, expires_in: CACHE_TTL) if ids.any?
        ids
      end

      # @param base_url [String]
      # @param api_key [String, nil]
      # @param fallback [String, nil]
      # @return [String, nil]
      def primary_id(base_url:, api_key: nil, fallback: nil)
        ids = list_ids(base_url: base_url, api_key: api_key)
        preferred = fallback.to_s.presence
        return preferred if preferred && ids.include?(preferred)

        ids.first || fallback.presence
      end

      def reset_cache!
        Rails.cache.delete_matched("chat/server_models/v1/*")
      rescue NotImplementedError
        nil
      end

      private

      def cache_key_for(base_url, api_key, suffix: "primary")
        digest = Digest::SHA256.hexdigest([ base_url, api_key.to_s, suffix ].join("|"))
        "chat/server_models/v1/#{digest}"
      end

      def fetch_ids(base_url:, api_key:)
        uri = models_uri(base_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{api_key}" if api_key.present?

        response = http.request(request)
        return [] unless response.is_a?(Net::HTTPSuccess)

        parse_ids(response.body.to_s)
      rescue StandardError
        []
      end

      def models_uri(base_url)
        root = base_url.to_s.strip.chomp("/").delete_suffix("/v1")
        URI("#{root}/v1/models")
      end

      def parse_ids(body)
        data = JSON.parse(body)
        Array(data["data"]).filter_map { |entry| entry["id"].to_s.presence }
      rescue JSON::ParserError
        []
      end
    end
  end
end
