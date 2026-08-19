# frozen_string_literal: true

require "test_helper"

class NyoyMcpSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_url = ENV["NYOY_MCP_URL"]
    @original_token = ENV["NYOY_MCP_API_TOKEN"]
    ENV.delete("NYOY_MCP_URL")
    ENV.delete("NYOY_MCP_API_TOKEN")
  end

  teardown do
    ENV["NYOY_MCP_URL"] = @original_url
    ENV["NYOY_MCP_API_TOKEN"] = @original_token
  end

  test "show requires authentication" do
    sign_out
    get nyoy_mcp_url
    assert_match %r{/login}, @response.redirect_url
  end

  test "show renders settings page when logged in" do
    get nyoy_mcp_url
    assert_response :success
    assert_includes response.body, "Nyoy MCP 設定"
    assert_includes response.body, "nyoy-mcp-settings"
  end

  test "show prefills effective url when account url is blank" do
    ENV["NYOY_MCP_URL"] = "https://nyoy.example/mcp"

    get nyoy_mcp_url

    assert_response :success
    assert_includes response.body, 'value="https://nyoy.example/mcp"'
    assert_includes response.body, "アカウント未保存"
  ensure
    ENV.delete("NYOY_MCP_URL")
  end

  test "update saves url and api token" do
    account = accounts(:one)
    patch nyoy_mcp_url, params: {
      account: {
        nyoy_mcp_url: "http://nyoy.test/mcp",
        nyoy_mcp_api_token: "secret-token"
      }
    }

    assert_redirected_to nyoy_mcp_url
    account.reload
    assert_equal "http://nyoy.test/mcp", account.nyoy_mcp_url
    assert_equal "secret-token", account.nyoy_mcp_api_token
    assert account.nyoy_mcp_configured?
  end

  test "update strips a Bearer prefix from the api token" do
    account = accounts(:one)
    patch nyoy_mcp_url, params: {
      account: {
        nyoy_mcp_url: "http://nyoy.test/mcp",
        nyoy_mcp_api_token: "Bearer secret-token"
      }
    }

    assert_redirected_to nyoy_mcp_url
    assert_equal "secret-token", account.reload.nyoy_mcp_api_token
  end

  test "update clears api token when requested" do
    account = accounts(:one)
    account.update!(nyoy_mcp_url: "http://nyoy.test/mcp", nyoy_mcp_api_token: "secret-token")

    patch nyoy_mcp_url, params: {
      account: { clear_nyoy_mcp_api_token: "1" }
    }

    assert_redirected_to nyoy_mcp_url
    account.reload
    assert_nil account.nyoy_mcp_api_token
  end

  test "test_connection returns tool list" do
    account = accounts(:one)
    account.update!(nyoy_mcp_url: "http://nyoy.test/mcp", nyoy_mcp_api_token: "secret-token")

    original = Chat::NyoyMcpClient.instance_method(:list_tools)
    begin
      Chat::NyoyMcpClient.define_method(:list_tools) do
        [ { "name" => "web_search", "description" => "Search" } ]
      end

      post test_connection_nyoy_mcp_url, as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal true, body["ok"]
      assert_equal 1, body["tool_count"]
    ensure
      Chat::NyoyMcpClient.define_method(:list_tools, original)
    end
  end

  test "test_connection uses form url and token without saving" do
    called_with = {}
    fake_client = Object.new
    fake_client.define_singleton_method(:list_tools) do
      [ { "name" => "fetch_url", "description" => "Fetch" } ]
    end

    original_new = Chat::NyoyMcpClient.method(:new)
    Chat::NyoyMcpClient.define_singleton_method(:new) do |**kwargs|
      called_with.replace(kwargs)
      fake_client
    end

    begin
      post test_connection_nyoy_mcp_url,
           params: {
             account: {
               nyoy_mcp_url: "http://nyoy.example/mcp",
               nyoy_mcp_api_token: "form-token"
             }
           },
           as: :json

      assert_response :success
      assert_equal "http://nyoy.example/mcp", called_with[:url]
      assert_equal "form-token", called_with[:api_token]
    ensure
      Chat::NyoyMcpClient.define_singleton_method(:new, original_new)
    end
  end

  test "test_connection requires token when none saved" do
    post test_connection_nyoy_mcp_url,
         params: { account: { nyoy_mcp_url: "http://nyoy.example/mcp" } },
         as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["message"], "API トークン"
  end
end
