require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "app responses include low-risk browser security headers" do
    get memos_url

    assert_response :success
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
    assert_equal "strict-origin-when-cross-origin", response.headers["Referrer-Policy"]
    assert_equal "camera=(), geolocation=(), microphone=()", response.headers["Permissions-Policy"]
    assert_includes response.headers["Content-Security-Policy-Report-Only"], "frame-ancestors 'self'"
  end
end
