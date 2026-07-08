# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Chat
  # OpenAI 互換 Chat Completions クライアント（llama-server / OpenAI / その他互換 API 共通）。
  # base_url を注入できる点が旧 OpenaiChatCompletion との違い。
  class LlmClient
    DEFAULT_TIMEOUT = 120
    DEFAULT_OPEN_TIMEOUT = 15

    class Error < StandardError
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    # @param base_url [String] OpenAI 互換 API のルート（例 http://localhost:10010 もしくは .../v1）
    # @param model [String]
    # @param api_key [String, nil] ローカル llama-server では通常不要
    # @param temperature [Float, nil]
    def initialize(base_url:, model:, api_key: nil, temperature: nil,
                   timeout: DEFAULT_TIMEOUT, open_timeout: DEFAULT_OPEN_TIMEOUT)
      @base_url = base_url.to_s
      @model = model.to_s
      @api_key = api_key.to_s
      @temperature = temperature
      @timeout = timeout
      @open_timeout = open_timeout
    end

    # @param messages [Array<Hash>] { role:, content: } の配列
    # @param temperature [Float, nil] 呼び出し単位の上書き
    # @param response_format [Hash, nil] 例 { "type" => "json_object" }
    # @return [String] assistant の本文
    def chat(messages, temperature: nil, response_format: nil)
      raise Error, "base_url が空です。" if @base_url.blank?
      raise Error, "model が空です。" if @model.blank?

      payload = { model: @model, messages: messages.map { |m| stringify_message(m) } }
      temp = temperature || @temperature
      payload[:temperature] = temp unless temp.nil?
      payload[:response_format] = response_format if response_format

      parse_assistant_content(http_post(payload))
    end

    private

    def stringify_message(message)
      role = message[:role] || message["role"]
      content = message[:content] || message["content"]
      { "role" => role.to_s, "content" => content.to_s }
    end

    def endpoint
      root = @base_url.strip.chomp("/")
      root = root.delete_suffix("/v1")
      URI("#{root}/v1/chat/completions")
    end

    def http_post(payload)
      uri = endpoint
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @timeout

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}" if @api_key.present?
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)

      response = http.request(request)
      body = response.body.to_s

      unless response.is_a?(Net::HTTPSuccess)
        message = extract_error_message(body) || "LLM API エラー（#{response.code}）"
        raise Error.new(message, status: response.code.to_i, body: body)
      end

      JSON.parse(body)
    rescue JSON::ParserError
      raise Error, "LLM API の応答を解析できませんでした。"
    end

    def extract_error_message(body)
      data = JSON.parse(body)
      err = data["error"]
      err.is_a?(Hash) ? err["message"].presence : nil
    rescue JSON::ParserError
      nil
    end

    def parse_assistant_content(data)
      choice = data.fetch("choices", []).first
      content = choice&.dig("message", "content").to_s.strip
      raise Error, "応答が空でした。" if content.blank?

      content
    end
  end
end
