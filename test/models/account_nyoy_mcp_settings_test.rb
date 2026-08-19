# frozen_string_literal: true

require "test_helper"

class AccountNyoyMcpSettingsTest < ActiveSupport::TestCase
  test "nyoy_mcp_configured when url and token present" do
    account = accounts(:one)
    account.update!(nyoy_mcp_url: "http://nyoy.test/mcp", nyoy_mcp_api_token: "token")

    assert account.nyoy_mcp_configured?
    assert_equal "http://nyoy.test/mcp", Chat::NyoyMcpConfig.url(account: account)
    assert_equal "token", Chat::NyoyMcpConfig.api_token(account: account)
    assert Chat::NyoyMcpConfig.configured?(account: account)
  end

  test "nyoy_mcp_configured is false when stored token cannot be decrypted" do
    account = accounts(:one)
    account.update!(nyoy_mcp_url: "http://nyoy.test/mcp", nyoy_mcp_api_token: "token")
    corrupt_encrypted_attribute!(account, :nyoy_mcp_api_token)

    assert account.nyoy_mcp_api_token_configured?
    assert_not account.nyoy_mcp_api_token_decryptable?
    assert_not account.nyoy_mcp_configured?
    assert_not_equal "token", Chat::NyoyMcpConfig.api_token(account: account).to_s
  end

  test "api_token strips a Bearer prefix and surrounding whitespace" do
    account = accounts(:one)
    account.update!(nyoy_mcp_url: "http://nyoy.test/mcp", nyoy_mcp_api_token: "Bearer secret-token\n")

    assert_equal "secret-token", Chat::NyoyMcpConfig.api_token(account: account)
    assert_equal "secret-token", Chat::NyoyMcpConfig.normalize_api_token("Bearer secret-token")
  end
end
