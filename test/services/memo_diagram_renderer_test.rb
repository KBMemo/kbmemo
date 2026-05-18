# frozen_string_literal: true

require "test_helper"

class MemoDiagramRendererTest < ActiveSupport::TestCase
  test "kroki_failure_message explains missing mermaid companion" do
    body = <<~SVG
      <svg><text><tspan>Error 503: Connection refused: /127.0.0.1:8002</tspan></text></svg>
    SVG
    response = Struct.new(:code, :body, :message).new("503", body, "Service Unavailable")
    renderer = MemoDiagramRenderer.new
    message = renderer.send(:kroki_failure_message, response)

    assert_includes message, "kroki-mermaid"
    assert_includes message, "docker compose"
    assert_equal Encoding::UTF_8, message.encoding
  end

  test "kroki_failure_message extracts readable line from svg error body" do
    body = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg">
        <text><tspan>Error 400: SyntaxError: No diagram type</tspan></text>
      </svg>
    SVG
    response = Struct.new(:code, :body, :message).new("400", body, "Bad Request")
    message = MemoDiagramRenderer.new.send(:kroki_failure_message, response)

    assert_includes message, "SyntaxError: No diagram type"
    assert_not_includes message, "<?xml"
  end

  test "kroki_failure_message coerces binary error body with japanese" do
    body = "<svg><text>構文エラー</text></svg>".b
    response = Struct.new(:code, :body, :message).new("400", body, "Bad Request")
    message = MemoDiagramRenderer.new.send(:kroki_failure_message, response)

    assert_equal Encoding::UTF_8, message.encoding
    assert_includes message, "構文エラー"
    assert_includes message, "Kroki エラー"
  end
end
