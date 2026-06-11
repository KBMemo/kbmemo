require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "app responses include low-risk browser security headers" do
    get memos_url

    assert_response :success
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
    assert_equal "same-origin-allow-popups", response.headers["Cross-Origin-Opener-Policy"]
    assert_equal "same-origin", response.headers["Cross-Origin-Resource-Policy"]
    assert_equal "strict-origin-when-cross-origin", response.headers["Referrer-Policy"]
    assert_equal "camera=(), geolocation=(), microphone=()", response.headers["Permissions-Policy"]
    assert_equal 'csp="/csp_reports"', response.headers["Reporting-Endpoints"]
    assert_includes response.headers["Content-Security-Policy-Report-Only"], "frame-ancestors 'self'"
    assert_includes response.headers["Content-Security-Policy-Report-Only"], "require-trusted-types-for 'script'"
    assert_includes response.headers["Content-Security-Policy-Report-Only"], "trusted-types kbmemo-adoc-preview-html kbmemo-sanitized-svg kbmemo-server-rendered-fragment"
    assert_includes response.headers["Content-Security-Policy-Report-Only"], "report-uri /csp_reports"
  end

  test "csp report endpoint accepts browser reports without authentication" do
    sign_out

    post "/csp_reports",
      params: {
        "csp-report" => {
          "document-uri" => "https://kbmemo.net/memos?token=secret",
          "effective-directive" => "script-src",
          "blocked-uri" => "inline"
        }
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/csp-report" }

    assert_response :no_content
  end
end
