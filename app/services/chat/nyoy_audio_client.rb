# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "uri"

module Chat
  class NyoyAudioClient
    class Error < StandardError; end

    def initialize(url:, api_token:)
      @mcp_url = url.to_s
      @api_token = Chat::NyoyMcpConfig.normalize_api_token(api_token).to_s
    end

    def configured?
      @mcp_url.present? && @api_token.present?
    end

    def synthesize(text)
      raise Error, "Nyoy MCP が未設定です。" unless configured?

      uri = endpoint("/api/audio/speech")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_token}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(input: text)
      response = perform(uri, request)
      raise Error, "Nyoy 音声合成に失敗しました（HTTP #{response.code}）" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    def transcribe(io:, filename:, content_type:)
      raise Error, "Nyoy MCP が未設定です。" unless configured?

      uri = endpoint("/api/audio/transcriptions")
      boundary = "----kbmemo-audio-#{SecureRandom.hex(12)}"
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_token}"
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request["Accept"] = "application/json"
      request.body = multipart_body(boundary, io.read, filename, content_type)
      response = perform(uri, request)
      payload = JSON.parse(response.body.to_s)
      return payload.fetch("text") if response.is_a?(Net::HTTPSuccess)

      raise Error, payload["error"].presence || "Nyoy 音声文字起こしに失敗しました（HTTP #{response.code}）"
    rescue JSON::ParserError
      raise Error, "Nyoy 音声文字起こしの応答を解析できませんでした。"
    end

    private

    def endpoint(path)
      uri = URI.parse(@mcp_url)
      uri.path = path
      uri.query = nil
      uri
    rescue URI::InvalidURIError => error
      raise Error.new("Nyoy MCP URL が不正です。"), cause: error
    end

    def perform(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 15
      http.read_timeout = 180
      http.request(request)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => error
      raise Error.new("Nyoy 音声 API に接続できませんでした: #{error.message}"), cause: error
    end

    def multipart_body(boundary, data, filename, content_type)
      parts = [
        "--#{boundary}\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nLiquidAI/LFM2.5-Audio-1.5B-JP\r\n",
        "--#{boundary}\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\nja\r\n",
        "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename.to_s.tr('\\\"', '_')}\"\r\nContent-Type: #{content_type}\r\n\r\n",
        data,
        "\r\n--#{boundary}--\r\n"
      ]
      parts.join
    end
  end
end
