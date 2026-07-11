# frozen_string_literal: true

require "test_helper"

module Chat
  class NyoyMcpClientTest < ActiveSupport::TestCase
    setup do
      @original_url = ENV["NYOY_MCP_URL"]
      @original_token = ENV["NYOY_MCP_API_TOKEN"]
      ENV["NYOY_MCP_URL"] = "http://nyoy.test/mcp"
      ENV["NYOY_MCP_API_TOKEN"] = "secret-token"
    end

    teardown do
      ENV["NYOY_MCP_URL"] = @original_url
      ENV["NYOY_MCP_API_TOKEN"] = @original_token
    end

    test "configured when url and token are present" do
      assert Chat::NyoyMcpClient.new.configured?
    end

    test "call_tool parses text payload" do
      client = Chat::NyoyMcpClient.new
      client.define_singleton_method(:rpc_request) do |**|
        {
          "result" => {
            "content" => [{ "type" => "text", "text" => JSON.generate({ "results" => [] }) }]
          }
        }
      end

      payload = client.call_tool(name: "web_search", arguments: { q: "test" })
      assert_equal [], payload["results"]
    end

    test "call_tool raises api error when tool returns isError" do
      client = Chat::NyoyMcpClient.new
      client.define_singleton_method(:rpc_request) do |**|
        {
          "result" => {
            "isError" => true,
            "content" => [{ "type" => "text", "text" => "budget exceeded" }]
          }
        }
      end

      error = assert_raises(Chat::NyoyMcpClient::ApiError) do
        client.call_tool(name: "web_search", arguments: { q: "test" })
      end
      assert_includes error.message, "budget exceeded"
    end

    test "call_tool raises not configured without token" do
      client = Chat::NyoyMcpClient.new(api_token: "")
      assert_raises(Chat::NyoyMcpClient::NotConfiguredError) do
        client.call_tool(name: "web_search", arguments: { q: "test" })
      end
    end

    test "list_tools returns normalized tool metadata" do
      client = Chat::NyoyMcpClient.new
      client.define_singleton_method(:rpc_request) do |**|
        {
          "result" => {
            "tools" => [
              { "name" => "web_search", "description" => "Search the web", "inputSchema" => { "type" => "object" } },
              { "name" => "mcp_auth", "description" => "Auth" }
            ]
          }
        }
      end

      tools = client.list_tools
      assert_equal 1, tools.size
      assert_equal "web_search", tools.first["name"]
      assert_equal "Search the web", tools.first["description"]
      assert_equal({ "type" => "object" }, tools.first["input_schema"])
    end

    test "list_tools explains 404 as disabled or wrong url" do
      client = Chat::NyoyMcpClient.new(url: "http://nyoy.test/mcp", api_token: "token")
      client.define_singleton_method(:rpc_request) do |**|
        raise Chat::NyoyMcpClient::ApiError.new(
          client.send(:http_error_message, 404, URI.parse("http://nyoy.test/mcp")),
          status: 404
        )
      end

      error = assert_raises(Chat::NyoyMcpClient::ApiError) do
        client.list_tools
      end
      assert_includes error.message, "404"
      assert_includes error.message, "MCP_API_TOKEN"
    end
  end
end
