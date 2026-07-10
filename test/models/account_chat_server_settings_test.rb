# frozen_string_literal: true

require "test_helper"

class AccountChatServerSettingsTest < ActiveSupport::TestCase
  test "normalize stores roles with base_url and model" do
    account = accounts(:one)
    account.update_chat_server_settings!(
      "roles" => {
        "main" => { "base_url" => "http://host:10011", "model" => "gemma" }
      }
    )

    payload = account.chat_server_settings_payload
    assert_equal "http://host:10011", payload.dig("roles", "main", "base_url")
    assert_equal "gemma", payload.dig("roles", "main", "model")
  end

  test "normalize migrates legacy base_urls and models keys" do
    normalized = Account.normalize_chat_server_settings(
      "base_urls" => { "intent" => "http://legacy:10010" },
      "models" => { "intent" => "legacy-model" }
    )

    assert_equal "http://legacy:10010", normalized.dig("roles", "intent", "base_url")
    assert_equal "legacy-model", normalized.dig("roles", "intent", "model")
  end
end
