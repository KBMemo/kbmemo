# frozen_string_literal: true

require "net/http"

# Kroki へソースを送り SVG を取得する。
class MemoDiagramRenderer
  class Error < StandardError; end
  class Unavailable < Error; end

  def self.render(engine:, source:, base_url: nil)
    new(base_url: base_url).render(engine: engine, source: source)
  end

  def self.resolved_base_url(explicit = nil)
    url = explicit.presence || Rails.application.config.x.kroki_url
    url = KrokiConfig::DEFAULT_URL if url.blank? || !url.to_s.match?(%r{\Ahttps?://}i)
    url.to_s.chomp("/")
  end

  def initialize(base_url: nil)
    @base_url = self.class.resolved_base_url(base_url)
  end

  def render(engine:, source:)
    kroki_type = MemoDiagram.kroki_type(engine)
    uri = URI.parse("#{@base_url}/#{kroki_type}/svg")
    response = post_svg(uri, source.to_s)
    raise Error, "Kroki が空の SVG を返しました" if response.body.blank?

    MemoSvgSanitizer.sanitize!(response.body)
  rescue MemoAssets::InvalidFile => e
    raise Error, e.message
  rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise Unavailable, "Kroki に接続できません（#{@base_url}）: #{e.message}"
  end

  private

  def kroki_failure_message(response)
    body = response.body.to_s
    if body.include?("127.0.0.1:8002") || body.include?(":8002")
      return "Mermaid 用の Kroki コンパニオン (kroki-mermaid) が起動していません。" \
             " `docker compose -f docker-compose.kroki.yml up -d` を実行してください。"
    end

    text = body[/>([^<]+Connection refused[^<]+)</, 1] ||
           body[/>([^<]+Error \d+:[^<]+)</, 1]
    detail = text&.strip.presence || body.strip.presence || response.message
    "Kroki エラー (#{response.code}): #{detail}"
  end

  def post_svg(uri, body)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 30) do |http|
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "text/plain"
      request["Accept"] = "image/svg+xml"
      request.body = body
      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, kroki_failure_message(response)
      end
      response
    end
  end
end
