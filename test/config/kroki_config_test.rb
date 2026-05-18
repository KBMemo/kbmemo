# frozen_string_literal: true

require "test_helper"

class KrokiConfigTest < ActiveSupport::TestCase
  test "resolve uses default for blank or invalid env" do
    with_env("KROKI_URL" => "{}") do
      assert_equal "http://localhost:8063", KrokiConfig.resolve
    end
    with_env("KROKI_URL" => "") do
      assert_equal "http://localhost:8063", KrokiConfig.resolve
    end
  end

  test "resolve keeps valid http url" do
    with_env("KROKI_URL" => "http://kroki.example:9999/") do
      assert_equal "http://kroki.example:9999", KrokiConfig.resolve
    end
  end

  private

  def with_env(hash)
    old = {}
    hash.each do |key, value|
      old[key] = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
