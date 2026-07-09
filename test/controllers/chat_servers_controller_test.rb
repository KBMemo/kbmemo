# frozen_string_literal: true

require "test_helper"

class ChatServersControllerTest < ActionDispatch::IntegrationTest
  test "show requires authentication" do
    sign_out
    get chat_server_url
    assert_match %r{/login}, @response.redirect_url
  end

  test "show renders settings page when logged in" do
    get chat_server_url
    assert_response :success
    assert_includes response.body, "Chat サーバー設定"
    assert_includes response.body, "chat-server"
    assert_includes response.body, "10010"
  end

  test "update saves per-role base urls" do
    account = accounts(:one)
    patch chat_server_url, params: {
      chat_server_settings: {
        base_urls: {
          intent: "http://pc-a.test:10010",
          main: "http://pc-b.test:10012",
          fast_chat: ""
        }
      }
    }

    assert_redirected_to chat_server_url
    account.reload
    assert_equal "http://pc-a.test:10010", account.chat_server_base_url(:intent)
    assert_equal "http://pc-b.test:10012", account.chat_server_base_url(:main)
    assert_nil account.chat_server_base_url(:fast_chat)
  end

  test "health_check returns json checks" do
    fake_results = [
      Chat::ServerHealth::Result.new(role: :intent, base_url: "http://balvenie:10010", ok: true, message: "OK (200)")
    ]

    original = Chat::ServerHealth.method(:check_all)
    begin
      Chat::ServerHealth.define_singleton_method(:check_all) { |**_| fake_results }

      post health_check_chat_server_url, as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 1, body["checks"].size
      assert_equal "intent", body["checks"].first["role"]
      assert_equal true, body["checks"].first["ok"]
    ensure
      Chat::ServerHealth.define_singleton_method(:check_all, original)
    end
  end
end
