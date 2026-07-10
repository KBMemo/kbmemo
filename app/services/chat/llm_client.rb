# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Chat
  # OpenAI 互換 Chat Completions クライアント（llama-server / OpenAI / その他互換 API 共通）。
  # base_url を注入できるので、ローカル llama-server も BYOK OpenAI も同一 IF で扱える。
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

    # 接続失敗（サーバ未起動・タイムアウト等）。API エラーと区別してフォールバック判定に使う。
    class ConnectionError < Error; end

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
    # @yield [Hash] { content:, thinking: } ストリーム chunk（stream: true 時）
    # @return [String] assistant の本文
    def chat(messages, temperature: nil, response_format: nil, stream: false, &block)
      raise Error, "base_url が空です。" if @base_url.blank?
      raise Error, "model が空です。" if @model.blank?

      payload = { model: @model, messages: messages.map { |m| stringify_message(m) } }
      temp = temperature || @temperature
      payload[:temperature] = temp unless temp.nil?
      payload[:response_format] = response_format if response_format
      payload[:stream] = true if stream

      if stream
        chat_stream(payload, &block)
      else
        parse_assistant_content(http_post(payload))
      end
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
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, SocketError, SystemCallError, IOError => e
      raise ConnectionError, "LLM API へ接続できませんでした: #{e.message}"
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
      message = choice&.fetch("message", {}) || {}
      content = message["content"].to_s.strip
      content = message["reasoning_content"].to_s.strip if content.blank?
      raise Error, "応答が空でした。" if content.blank?

      content
    end

    def chat_stream(payload, &block)
      uri = endpoint
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @timeout

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}" if @api_key.present?
      request["Content-Type"] = "application/json"
      request["Accept"] = "text/event-stream"
      request.body = JSON.generate(payload)

      assistant_content = +""
      assistant_thinking = +""

      handle_delta = lambda do |delta|
        thinking = delta[:thinking].to_s
        content = delta[:content].to_s
        assistant_thinking << thinking if thinking.present?
        assistant_content << content if content.present?
        block&.call(delta) if thinking.present? || content.present?
      end

      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          body = response.body.to_s
          message = extract_error_message(body) || "LLM API エラー（#{response.code}）"
          raise Error.new(message, status: response.code.to_i, body: body)
        end

        buffer = +""
        response.read_body do |chunk|
          buffer << chunk
          while (line = buffer.slice!(/\A[^\n]*\n/m))
            process_sse_line(line, &handle_delta)
          end
        end

        buffer.each_line { |line| process_sse_line(line, &handle_delta) }
      end

      content = assistant_content.strip
      content = assistant_thinking.strip if content.blank?
      raise Error, "応答が空でした。" if content.blank?

      content
    rescue JSON::ParserError
      raise Error, "LLM API の応答を解析できませんでした。"
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, SocketError, SystemCallError, IOError => e
      raise ConnectionError, "LLM API へ接続できませんでした: #{e.message}"
    end

    def process_sse_line(line, &block)
      line = line.strip
      return if line.empty?
      return unless line.start_with?("data:")

      data = line.delete_prefix("data:").strip
      return if data == "[DONE]"

      delta = parse_stream_delta(JSON.parse(data))
      return unless delta

      thinking = delta[:thinking].to_s
      content = delta[:content].to_s
      block.call(delta) if thinking.present? || content.present?
    end

    def parse_stream_delta(data)
      choice = data.fetch("choices", []).first
      delta = choice&.fetch("delta", {}) || {}
      content = delta["content"]
      thinking = delta["reasoning_content"]
      return nil if content.blank? && thinking.blank?

      { content: content.to_s, thinking: thinking.to_s }
    end
  end
end
