# frozen_string_literal: true

require "test_helper"

class Api::V1::MeControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_out
    @account = accounts(:one)
    @token = @account.generate_api_token!
  end

  test "show returns current account" do
    get api_v1_me_path, headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @account.id, body["id"]
    assert_equal @account.email, body["email"]
    assert_equal "account_api_token", body["token_type"]
  end

  test "show without token returns unauthorized" do
    get api_v1_me_path, headers: { "Accept" => "application/json" }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "unauthorized", body.dig("error", "code")
  end

  test "web clip token cannot access account api" do
    @token = @account.generate_web_clip_token!

    get api_v1_me_path, headers: auth_headers

    assert_response :unauthorized
  end

  private

  def auth_headers
    {
      "Authorization" => "Bearer #{@token}",
      "Accept" => "application/json",
      "Content-Type" => "application/json"
    }
  end
end
