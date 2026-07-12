# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Chat
  # Nyoy MCP Streamable HTTP クライアント（stateless / JSON 応答）。
  class NyoyMcpClient
    DEFAULT_TIMEOUT = 90
    DEFAULT_OPEN_TIMEOUT = 15

    class Error < StandardError
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    class NotConfiguredError < Error; end
    class ConnectionError < Error; end
    class ApiError < Error; end

    def initialize(url: nil, api_token: nil, timeout: DEFAULT_TIMEOUT, open_timeout: DEFAULT_OPEN_TIMEOUT)
      @url = (url || NyoyMcpConfig.url).to_s.strip.chomp("/")
      @api_token = (api_token || NyoyMcpConfig.api_token).to_s.strip
      @timeout = timeout
      @open_timeout = open_timeout
      @request_id = 0
    end

    def configured?
      @url.present? && @api_token.present?
    end

    def site_origin
      uri = URI.parse(@url)
      origin = "#{uri.scheme}://#{uri.host}"
      origin += ":#{uri.port}" if uri.port && ![ 80, 443 ].include?(uri.port)
      origin
    rescue URI::InvalidURIError
      nil
    end

    def list_tools
      ensure_configured!
      response = rpc_request(method: "tools/list", params: {})
      if response["error"].present?
        message = response.dig("error", "message").presence || "Nyoy MCP RPC エラー"
        raise ApiError, message
      end

      Array(response.dig("result", "tools")).filter_map do |tool|
        name = tool["name"].to_s
        next if name.blank? || name == "mcp_auth"

        {
          "name" => name,
          "description" => tool["description"].to_s,
          "input_schema" => tool["inputSchema"] || tool["input_schema"] || {}
        }
      end
    end

    def call_tool(name:, arguments: {})
      ensure_configured!
      parse_result(
        rpc_request(
          method: "tools/call",
          params: {
            name: name.to_s,
            arguments: arguments || {}
          }
        )
      )
    end

    private

    def ensure_configured!
      raise NotConfiguredError, "Nyoy MCP の URL または API トークンが未設定です。" unless configured?
    end

    def rpc_request(method:, params:)
      payload = {
        jsonrpc: "2.0",
        id: next_request_id,
        method: method,
        params: params
      }

      uri = URI.parse(@url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "Bearer #{@api_token}"
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = JSON.generate(payload)

      response = http.request(request)
      body = response.body.to_s

      unless response.is_a?(Net::HTTPSuccess)
        message = extract_rpc_error(body) || http_error_message(response.code, uri)
        raise ApiError.new(message, status: response.code.to_i, body: body)
      end

      JSON.parse(body)
    rescue JSON::ParserError
      raise ApiError, "Nyoy MCP の応答を解析できませんでした。"
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, SocketError, SystemCallError, IOError => e
      raise ConnectionError, "Nyoy MCP へ接続できませんでした: #{e.message}"
    end

    def parse_result(response)
      if response["error"].present?
        message = response.dig("error", "message").presence || "Nyoy MCP RPC エラー"
        raise ApiError, message
      end

      result = response["result"] || {}
      if result["isError"]
        text = result.dig("content", 0, "text").to_s
        raise ApiError, text.presence || "Nyoy MCP ツールエラー"
      end

      text = result.dig("content", 0, "text")
      return {} if text.blank?

      JSON.parse(text)
    rescue JSON::ParserError
      text
    end

    def extract_rpc_error(body)
      data = JSON.parse(body)
      data.dig("error", "message").presence
    rescue JSON::ParserError
      nil
    end

    def next_request_id
      @request_id += 1
    end

    def http_error_message(code, uri)
      case code.to_i
      when 404
        "Nyoy MCP API エラー（404）— #{uri} が見つかりません。URL（例: https://host/mcp）を確認するか、接続先 Nyoy で MCP_API_TOKEN が設定されているか確認してください。"
      when 401, 403
        "Nyoy MCP API エラー（#{code}）— API トークンが正しくないか、接続先で MCP が拒否しました。"
      else
        "Nyoy MCP API エラー（#{code}）"
      end
    end
  end
end
