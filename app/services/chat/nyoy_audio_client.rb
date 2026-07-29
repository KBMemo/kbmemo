# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Chat
  class NyoyAudioClient
    class Error < StandardError; end

    def initialize(url:, api_token:)
      @mcp_url = url.to_s
      @api_token = api_token.to_s
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
  end
end
