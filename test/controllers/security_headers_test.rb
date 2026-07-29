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
    assert_match(/style-src 'self' 'nonce-[^']+'/, response.headers["Content-Security-Policy-Report-Only"])
    assert_includes response.headers["Content-Security-Policy-Report-Only"], "trusted-types default kbmemo-adoc-preview-html kbmemo-code-highlight-html kbmemo-sanitized-svg kbmemo-server-rendered-fragment"
    assert_includes response.headers["Content-Security-Policy-Report-Only"], "report-to csp"
    assert_includes response.headers["Content-Security-Policy-Report-Only"], "report-uri /csp_reports"
  end

  test "csp report endpoint accepts browser reports without authentication" do
    sign_out

    post "/csp_reports",
      params: {
        "csp-report" => {
          "document-uri" => "https://kbmemo.example.com/memos?token=secret",
          "effective-directive" => "script-src",
          "blocked-uri" => "inline"
        }
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/csp-report" }

    assert_response :no_content
  end

  test "csp report logging keeps source location without logging inline content" do
    controller = CspReportsController.new
    report = {
      "source-file" => "https://kbmemo.example.com/vite/assets/application.js",
      "line-number" => 42,
      "column-number" => 7,
      "script-sample" => "sensitive inline style"
    }

    captured = nil
    Rails.logger.stub(:info, ->(value) { captured = JSON.parse(value) }) do
      controller.send(:log_report, report)
    end

    assert_equal "https://kbmemo.example.com/vite/assets/application.js", captured.dig("report", "source_file")
    assert_equal "42", captured.dig("report", "line_number")
    assert_equal "7", captured.dig("report", "column_number")
    assert_nil captured.dig("report", "script_sample")
  end

  test "logout response clears browser site data" do
    post "/logout"

    assert_response :redirect
    assert_equal '"cookies", "storage", "cache"', response.headers["Clear-Site-Data"]
  end

  test "session cookie uses same-site lax" do
    assert_equal :lax, Rails.application.config.session_options[:same_site]
  end
end
