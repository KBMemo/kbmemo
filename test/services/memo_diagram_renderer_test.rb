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
  end
end
