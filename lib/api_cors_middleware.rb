# frozen_string_literal: true

# /api/* へのクロスオリジン clip リクエスト用 CORS。
# before_action だけでは認証失敗時など一部レスポンスにヘッダーが付かないため、
# Rack 層で常に付与する。
class ApiCorsMiddleware
  ALLOW_ORIGIN = "*"
  ALLOW_METHODS = "GET, POST, PATCH, PUT, DELETE, OPTIONS"
  ALLOW_HEADERS = "Authorization, Content-Type, Accept"
  MAX_AGE = "86400"

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless api_path?(env)

    if env["REQUEST_METHOD"] == "OPTIONS"
      return cors_response(204, [])
    end

    status, headers, body = @app.call(env)
    apply_cors_headers!(headers)
    [status, headers, body]
  end

  private

  def api_path?(env)
    env["PATH_INFO"].to_s.start_with?("/api/")
  end

  def apply_cors_headers!(headers)
    headers["Access-Control-Allow-Origin"] = ALLOW_ORIGIN
    headers["Access-Control-Allow-Methods"] = ALLOW_METHODS
    headers["Access-Control-Allow-Headers"] = ALLOW_HEADERS
    headers["Access-Control-Max-Age"] = MAX_AGE
  end

  def cors_response(status, body)
    headers = {
      "Access-Control-Allow-Origin" => ALLOW_ORIGIN,
      "Access-Control-Allow-Methods" => ALLOW_METHODS,
      "Access-Control-Allow-Headers" => ALLOW_HEADERS,
      "Access-Control-Max-Age" => MAX_AGE
    }
    [status, headers, body]
  end
end
