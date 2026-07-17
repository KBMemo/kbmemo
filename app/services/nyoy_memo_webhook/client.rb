# frozen_string_literal: true

require "net/http"

module NyoyMemoWebhook
  class Client
    class Error < StandardError; end
    class NotConfiguredError < Error; end

    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 10

    def self.configured?
      new.configured?
    end

    def initialize(
      url: ENV["NYOY_MEMO_WEBHOOK_URL"],
      secret: ENV["NYOY_MEMO_WEBHOOK_SECRET"],
      enabled: ENV["NYOY_MEMO_WEBHOOK_ENABLED"]
    )
      @url = url.to_s.strip
      @secret = secret.to_s
      @enabled = ActiveModel::Type::Boolean.new.cast(enabled)
    end

    def configured?
      @enabled && @url.present? && @secret.present?
    end

    def post!(payload)
      raise NotConfiguredError, "Nyoy memo webhook is not configured" unless configured?

      uri = URI.parse(@url)
      raise Error, "Nyoy memo webhook URL must be HTTP or HTTPS" unless uri.is_a?(URI::HTTP)

      raw_body = JSON.generate(payload)
      timestamp = Time.current.to_i.to_s
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["X-KBMemo-Webhook-Timestamp"] = timestamp
      request["X-KBMemo-Signature"] = Signature.sign(
        raw_body: raw_body,
        timestamp: timestamp,
        secret: @secret
      )
      request.body = raw_body

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |http| http.request(request) }

      return true if response.is_a?(Net::HTTPSuccess)

      raise Error, "Nyoy memo webhook failed: HTTP #{response.code}"
    rescue URI::InvalidURIError => e
      raise Error, "Invalid Nyoy memo webhook URL: #{e.message}"
    end
  end
end
