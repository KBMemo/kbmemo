# frozen_string_literal: true

require "net/http"
require "json"

module AgentChat
  # ログイン Cookie を Tsuzura に転送して画像を batch upload する。
  class TsuzuraUpload
    class Error < StandardError; end

    Result = Struct.new(:tsuzura_media_id, :filename, keyword_init: true)

    def self.call(file:, cookie_header:)
      new(file:, cookie_header:).call
    end

    def initialize(file:, cookie_header:)
      @file = file
      @cookie_header = cookie_header.to_s.strip
    end

    def call
      raise Error, "ファイルが空です。" unless @file.respond_to?(:read)

      uri = URI.join(Tsuzura::Endpoints.api_base_url, "/v1/media/batch")
      request = Net::HTTP::Post.new(uri)
      request["Cookie"] = @cookie_header if @cookie_header.present?
      request.set_form(
        [ [ "files[]", @file, { filename: sanitized_filename, content_type: content_type } ] ],
        "multipart/form-data"
      )

      response = http(uri).request(request)
      unless response.is_a?(Net::HTTPSuccess)
        message = extract_error(response.body) || "Tsuzura へのアップロードに失敗しました（#{response.code}）。"
        raise Error, message
      end

      payload = JSON.parse(response.body)
      media_id = extract_media_id(payload)
      raise Error, "Tsuzura からメディア ID を取得できませんでした。" if media_id.blank?

      Result.new(tsuzura_media_id: media_id, filename: sanitized_filename)
    rescue JSON::ParserError
      raise Error, "Tsuzura の応答を解析できませんでした。"
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      raise Error, "Tsuzura へ接続できませんでした: #{e.message}"
    end

    private

    def sanitized_filename
      @file.original_filename.to_s.presence || "upload.jpg"
    end

    def content_type
      @file.content_type.to_s.presence || "application/octet-stream"
    end

    def extract_media_id(payload)
      item = Array(payload["items"]).first ||
             Array(payload["media_items"]).first ||
             Array(payload["created"]).first
      if item.is_a?(Hash)
        id = item["id"].presence || item["media_item_id"].presence || item["media_id"].presence
        return id.to_s.upcase if id.present?
      end

      payload.dig("item", "id").to_s.upcase.presence ||
        payload["media_id"].to_s.upcase.presence ||
        payload["media_item_id"].to_s.upcase.presence
    end

    def extract_error(body)
      data = JSON.parse(body.to_s)
      data["error"].presence || data["message"].presence
    rescue JSON::ParserError
      nil
    end

    def http(uri)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 5,
        read_timeout: 120
      )
    end
  end
end
