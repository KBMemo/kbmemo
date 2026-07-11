# frozen_string_literal: true

require "net/http"

module AgentChat
  # Agent Chat 用: ログイン Cookie で Tsuzura からオリジナル画像を取得する。
  class TsuzuraMediaFile
    class Error < StandardError; end

    Result = Struct.new(:bytes, :content_type, keyword_init: true)

    def self.fetch(media_id:, cookie_header:)
      new(media_id:, cookie_header:).fetch
    end

    def initialize(media_id:, cookie_header:)
      @media_id = media_id.to_s.strip.upcase
      @cookie_header = cookie_header.to_s.strip
    end

    def fetch
      raise Error, "メディア ID が空です。" if @media_id.blank?
      raise Error, "Tsuzura へのアクセスに Cookie が必要です。" if @cookie_header.blank?

      uri = URI.join(Tsuzura::Endpoints.api_base_url, "/v1/media/#{@media_id}/file")
      request = Net::HTTP::Get.new(uri)
      request["Cookie"] = @cookie_header

      response = http(uri).request(request)
      unless response.is_a?(Net::HTTPSuccess)
        message = extract_error(response.body) || "Tsuzura から画像を取得できませんでした（#{response.code}）。"
        raise Error, message
      end

      content_type = response.content_type.presence || "application/octet-stream"
      Result.new(bytes: response.body.b, content_type: content_type)
    rescue JSON::ParserError
      raise Error, "Tsuzura の応答を解析できませんでした。"
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      raise Error, "Tsuzura へ接続できませんでした: #{e.message}"
    end

    private

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
