# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Chat
  # llama-server の /embedding API クライアント（LFM2.5-Embedding-350M 等）。
  class EmbeddingClient
    QUERY_PREFIX = "query: "
    DOCUMENT_PREFIX = "passage: "

    DEFAULT_TIMEOUT = 60
    DEFAULT_OPEN_TIMEOUT = 15

    class Error < StandardError
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    class ConnectionError < Error; end

    def initialize(base_url:, model: nil, timeout: DEFAULT_TIMEOUT, open_timeout: DEFAULT_OPEN_TIMEOUT)
      @base_url = base_url.to_s
      @model = model
      @timeout = timeout
      @open_timeout = open_timeout
    end

    # @param text [String]
    # @param kind [Symbol] :query または :document（LFM2.5 の prefix 付与）
    # @return [Array<Float>]
    def embed(text, kind: :document)
      raise Error, "base_url が空です。" if @base_url.blank?

      content = prefix_for(kind) + text.to_s
      parse_embedding(http_post(content))
    end

    private

    def prefix_for(kind)
      kind.to_sym == :query ? QUERY_PREFIX : DOCUMENT_PREFIX
    end

    def endpoint
      root = @base_url.strip.chomp("/").delete_suffix("/v1")
      URI("#{root}/embedding")
    end

    def http_post(content)
      uri = endpoint
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @open_timeout
      http.read_timeout = @timeout

      payload = { content: content }
      payload[:model] = @model if @model.present?

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)

      response = http.request(request)
      body = response.body.to_s

      unless response.is_a?(Net::HTTPSuccess)
        message = extract_error_message(body) || "Embedding API エラー（#{response.code}）"
        raise Error.new(message, status: response.code.to_i, body: body)
      end

      JSON.parse(body)
    rescue JSON::ParserError
      raise Error, "Embedding API の応答を解析できませんでした。"
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, SocketError, SystemCallError, IOError => e
      raise ConnectionError, "Embedding API へ接続できませんでした: #{e.message}"
    end

    def extract_error_message(body)
      data = JSON.parse(body)
      err = data["error"]
      err.is_a?(Hash) ? err["message"].presence : nil
    rescue JSON::ParserError
      nil
    end

    def parse_embedding(data)
      vector = extract_embedding_vector(data)
      values = flatten_embedding(vector)
      raise Error, "埋め込みベクトルが空でした。" if values.empty?

      values
    end

    def extract_embedding_vector(data)
      case data
      when Array
        data.first&.dig("embedding")
      when Hash
        data.dig("data", 0, "embedding") || data["embedding"]
      end
    end

    # llama-server /embedding は [[float, ...]] の二重配列を返すことがある。
    def flatten_embedding(vector)
      case vector
      when nil
        []
      when Array
        if vector.empty?
          []
        elsif vector.all? { |v| v.is_a?(Numeric) }
          vector.map(&:to_f)
        else
          flatten_embedding(vector.first)
        end
      else
        []
      end
    end
  end
end
