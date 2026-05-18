# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# OpenAI Chat Completions API（ユーザー BYOK キー用）。
class OpenaiChatCompletion
  ENDPOINT = URI("https://api.openai.com/v1/chat/completions")
  DEFAULT_MODEL = "gpt-4o-mini"
  TIMEOUT = 120

  class Error < StandardError
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end

  def initialize(api_key:, model: DEFAULT_MODEL)
    @api_key = api_key.to_s
    @model = model.presence || DEFAULT_MODEL
  end

  # @param messages [Array<Hash>] OpenAI 形式 { "role" => "user"|"assistant"|"system", "content" => "..." }
  # @return [String] assistant の本文
  def call(messages)
    raise Error, "API キーが空です。" if @api_key.blank?

    payload = {
      model: @model,
      messages: messages.map { |m| stringify_message(m) }
    }

    response = http_post(payload)
    parse_assistant_content(response)
  end

  private

  def stringify_message(message)
    role = message[:role] || message["role"]
    content = message[:content] || message["content"]
    { "role" => role.to_s, "content" => content.to_s }
  end

  def http_post(payload)
    http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = TIMEOUT

    request = Net::HTTP::Post.new(ENDPOINT)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)

    response = http.request(request)
    body = response.body.to_s

    unless response.is_a?(Net::HTTPSuccess)
      message = extract_error_message(body) || "OpenAI API エラー（#{response.code}）"
      raise Error.new(message, status: response.code.to_i, body: body)
    end

    JSON.parse(body)
  rescue JSON::ParserError
    raise Error, "OpenAI API の応答を解析できませんでした。"
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
    content = choice&.dig("message", "content")
    content = content.to_s.strip
    raise Error, "応答が空でした。" if content.blank?

    content
  end
end
