# frozen_string_literal: true

# Kroki（Mermaid / PlantUML 等の SVG 変換）。未起動時はダイアグラム保存でエラーになる。
module KrokiConfig
  DEFAULT_URL = "http://localhost:8001"

  module_function

  def resolve
    raw = ENV.fetch("KROKI_URL", DEFAULT_URL).to_s.strip
    return DEFAULT_URL if raw.blank?
    return DEFAULT_URL unless raw.match?(%r{\Ahttps?://}i)

    raw.chomp("/")
  end
end

Rails.application.config.x.kroki_url = KrokiConfig.resolve
