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
end
