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
    assert_includes response.body, "モデル取得"
    assert_includes response.body, "http://localhost:10011"
  end

  test "update saves per-role url and model" do
    account = accounts(:one)
    patch chat_server_url, params: {
      chat_server_settings: {
        roles: {
          intent: { base_url: "http://pc-a.test:10010", model: "intent-model" },
          main: { base_url: "http://pc-b.test:10012", model: "main-model" },
          fast_chat: { base_url: "", model: "" }
        }
      }
    }

    assert_redirected_to chat_server_url
    account.reload
    assert_equal "http://pc-a.test:10010", account.chat_server_base_url(:intent)
    assert_equal "intent-model", account.chat_server_model(:intent)
    assert_equal "http://pc-b.test:10012", account.chat_server_base_url(:main)
    assert_equal "main-model", account.chat_server_model(:main)
    assert_nil account.chat_server_base_url(:fast_chat)
  end

  test "health_check returns json checks" do
    fake_results = [
      Chat::ServerHealth::Result.new(
        role: :intent,
        base_url: "http://localhost:10010",
        ok: true,
        message: "OK (200)",
        model: "lfm2.5-1.2b"
      )
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

  test "model_options returns current memo assist model names" do
    account = accounts(:one)
    account.update_chat_server_settings!(
      "roles" => {
        "main" => { "base_url" => "http://main.test", "model" => "new-main" },
        "fast_chat" => { "base_url" => "http://fast.test", "model" => "new-fast" }
      }
    )

    get model_options_chat_server_url, as: :json

    assert_response :success
    options = JSON.parse(response.body).fetch("options").index_by { |entry| entry["role"] }
    assert_equal "new-main", options.dig("main", "model")
    assert_equal "new-fast", options.dig("fast_chat", "model")
  end

  test "health_check passes form role overrides to server health" do
    captured = nil
    original = Chat::ServerHealth.method(:check_all)
    begin
      Chat::ServerHealth.define_singleton_method(:check_all) do |**kwargs|
        captured = kwargs
        [
          Chat::ServerHealth::Result.new(
            role: :intent,
            base_url: "http://form.test:10010",
            ok: true,
            message: "OK (200)",
            model: "form-model"
          )
        ]
      end

      post health_check_chat_server_url,
        params: {
          chat_server_settings: {
            roles: {
              intent: { base_url: "http://form.test:10010", model: "form-model" }
            }
          }
        },
        as: :json

      assert_response :success
      assert_equal "http://form.test:10010",
        captured[:role_overrides].dig("roles", "intent", "base_url")
      assert_equal "form-model", captured[:role_overrides].dig("roles", "intent", "model")
    ensure
      Chat::ServerHealth.define_singleton_method(:check_all, original)
    end
  end

  test "list_models returns model ids from server" do
    original = Chat::ServerModels.method(:list_ids)
    begin
      Chat::ServerModels.define_singleton_method(:list_ids) do |**_|
        [ "model-a", "model-b" ]
      end

      post list_models_chat_server_url, params: { role: "main", base_url: "http://llm.test:10011" }, as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal [ "model-a", "model-b" ], body["models"]
    ensure
      Chat::ServerModels.define_singleton_method(:list_ids, original)
    end
  end

  test "list_models rejects blank base_url" do
    post list_models_chat_server_url, params: { role: "main", base_url: "" }, as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["error"], "接続 URL"
  end
end
