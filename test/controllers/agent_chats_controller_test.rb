# frozen_string_literal: true

require "test_helper"

class AgentChatsControllerTest < ActionDispatch::IntegrationTest
  test "show requires authentication" do
    sign_out
    get agent_chat_url
    assert_match %r{/login}, @response.redirect_url
  end

  test "show renders chat page when logged in" do
    get agent_chat_url
    assert_response :success
    assert_includes response.body, "agent-chat"
    assert_includes response.body, "AI チャット"
    assert_includes response.body, "Nyoy MCP"
  end

  test "show restores persisted conversation messages" do
    conversation = accounts(:one).agent_chat_conversations.create!(title: "履歴")
    conversation.messages.create!(role: "user", content: "以前の質問", metadata: {})
    conversation.messages.create!(
      role: "assistant",
      content: "以前の回答",
      intent: "chat",
      model_role: "fast_chat",
      metadata: { "escalated" => false, "pending_tools" => false }
    )

    get agent_chat_url

    assert_response :success
    assert_includes response.body, "以前の質問"
    assert_includes response.body, "以前の回答"
    assert_includes response.body, "data-agent-chat-target=\"initialMessagesJson\""
    assert_includes response.body, "data-agent-chat-conversation-id-value=\"#{conversation.id}\""
    assert_includes response.body, "agent-chat-conversation-list"
    assert_includes response.body, "履歴"
  end

  test "show loads conversation by id" do
    older = accounts(:one).agent_chat_conversations.create!(title: "古い", updated_at: 2.days.ago)
    older.messages.create!(role: "user", content: "古い質問", metadata: {})

    newer = accounts(:one).agent_chat_conversations.create!(title: "新しい", updated_at: 1.hour.ago)
    newer.messages.create!(role: "user", content: "新しい質問", metadata: {})

    get agent_chat_path(conversation_id: older.id)

    assert_response :success
    assert_includes response.body, "古い質問"
    refute_includes response.body, "新しい質問"
  end

  test "show with new param starts empty chat" do
    conversation = accounts(:one).agent_chat_conversations.create!(title: "履歴")
    conversation.messages.create!(role: "user", content: "以前の質問", metadata: {})

    get agent_chat_path(new: 1)

    assert_response :success
    refute_includes response.body, "以前の質問"
    assert_includes response.body, 'data-agent-chat-conversation-id-value=""'
  end

  test "nyoy_tools returns tool list" do
    original = Chat::NyoyMcpClient.instance_method(:list_tools)
    original_url = ENV["NYOY_MCP_URL"]
    original_token = ENV["NYOY_MCP_API_TOKEN"]
    ENV["NYOY_MCP_URL"] = "http://nyoy.test/mcp"
    ENV["NYOY_MCP_API_TOKEN"] = "secret-token"
    begin
      Chat::NyoyMcpClient.define_method(:list_tools) do
        [ { "name" => "web_search", "description" => "Search" } ]
      end

      get nyoy_tools_agent_chat_url, as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal true, body["configured"]
      assert_equal "web_search", body["tools"].first["name"]
    ensure
      Chat::NyoyMcpClient.define_method(:list_tools, original)
      ENV["NYOY_MCP_URL"] = original_url
      ENV["NYOY_MCP_API_TOKEN"] = original_token
    end
  end

  test "memo_references searches only visible memos" do
    hidden = Memo.create!(
      title: "Secret reference",
      body: "private",
      account: accounts(:two),
      memo_directory: memo_directories(:home_u_two),
      visibility: :owner_read_write
    )

    get memo_references_agent_chat_url, params: { q: "memo" }, as: :json

    assert_response :success
    ids = JSON.parse(response.body).fetch("memos").pluck("id")
    assert_includes ids, memos(:one).id
    refute_includes ids, hidden.id
  end

  test "create resolves and persists memo references" do
    captured = {}
    fake_result = Chat::Agent::Result.new(
      reply: "ok", intent: "conversation", classification: nil, model_role: :fast_chat,
      escalated: false, tools: [], pending_tools: false, rag: nil
    )
    original_new = Chat::Agent.method(:new)
    begin
      Chat::Agent.define_singleton_method(:new) do |**_kwargs|
        Object.new.tap do |agent|
          agent.define_singleton_method(:call) do |**kwargs|
            captured.replace(kwargs)
            fake_result
          end
        end
      end

      post agent_chat_url,
        params: {
          messages: [ { role: "user", content: "このメモを要約して" } ],
          memo_reference_ids: [ memos(:one).id ]
        },
        as: :json

      assert_response :success
      assert_equal [ memos(:one).id ], captured[:memo_references].map(&:id)
      conversation = AgentChatConversation.find(JSON.parse(response.body)["conversation_id"])
      assert_equal "First memo", conversation.messages.ordered.first.metadata.dig("memo_references", 0, "title")
    ensure
      Chat::Agent.define_singleton_method(:new, original_new)
    end
  end

  test "refine_image_generation calls nyoy refine_image and returns normalized status" do
    calls = []
    client = Object.new
    client.define_singleton_method(:site_origin) { "https://nyoy.example" }
    client.define_singleton_method(:call_tool) do |name:, arguments:|
      calls << [ name.to_s, arguments ]
      case name.to_s
      when "refine_image"
        { "id" => arguments[:id] || arguments["id"] }
      when "get_image_generation"
        {
          "id" => arguments[:id] || arguments["id"],
          "status" => "refining",
          "show_path" => "/image_generations/#{arguments[:id] || arguments["id"]}"
        }
      else
        raise "unexpected tool #{name}"
      end
    end

    original_client = Chat::NyoyMcpConfig.method(:client)
    original_configured = Chat::NyoyMcpConfig.method(:configured?)
    begin
      Chat::NyoyMcpConfig.define_singleton_method(:client) { |account: nil| client }
      Chat::NyoyMcpConfig.define_singleton_method(:configured?) { |account: nil| true }

      post refine_image_generation_agent_chat_url(42),
        params: { draft_index: 2 },
        as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "refining", body["status"]
      assert_equal "https://nyoy.example/image_generations/42", body["show_url"]
      assert_equal [
        [ "refine_image", { id: 42, draft_index: 2 } ],
        [ "get_image_generation", { id: 42 } ]
      ], calls
    ensure
      Chat::NyoyMcpConfig.define_singleton_method(:client, original_client)
      Chat::NyoyMcpConfig.define_singleton_method(:configured?, original_configured)
    end
  end

  test "refine_image_generation persists completed image url to conversation metadata" do
    conversation = accounts(:one).agent_chat_conversations.create!
    message = conversation.messages.create!(
      role: "assistant",
      content: "ラフ案です",
      intent: "image_generation",
      model_role: "main",
      metadata: {
        "mcp" => {
          "image_urls" => [ "https://nyoy.example/draft.png" ],
          "image_generation_watch" => { "id" => 42, "status" => "awaiting_selection" }
        }
      }
    )

    client = Object.new
    client.define_singleton_method(:site_origin) { "https://nyoy.example" }
    client.define_singleton_method(:call_tool) do |name:, arguments:|
      case name.to_s
      when "refine_image"
        { "id" => arguments[:id] || arguments["id"] }
      when "get_image_generation"
        {
          "id" => arguments[:id] || arguments["id"],
          "status" => "completed",
          "image_url" => "/rails/active_storage/final.png",
          "show_path" => "/image_generations/#{arguments[:id] || arguments["id"]}"
        }
      else
        raise "unexpected tool #{name}"
      end
    end

    original_client = Chat::NyoyMcpConfig.method(:client)
    original_configured = Chat::NyoyMcpConfig.method(:configured?)
    begin
      Chat::NyoyMcpConfig.define_singleton_method(:client) { |account: nil| client }
      Chat::NyoyMcpConfig.define_singleton_method(:configured?) { |account: nil| true }

      post refine_image_generation_agent_chat_url(42),
        params: { draft_index: 1, conversation_id: conversation.id },
        as: :json

      assert_response :success
      assert_equal [
        "https://nyoy.example/rails/active_storage/final.png"
      ], message.reload.metadata.dig("mcp", "image_urls")
      assert_equal "completed", message.metadata.dig("mcp", "image_generation_watch", "status")
    ensure
      Chat::NyoyMcpConfig.define_singleton_method(:client, original_client)
      Chat::NyoyMcpConfig.define_singleton_method(:configured?, original_configured)
    end
  end

  test "refine_image_generation rejects invalid draft index" do
    original_configured = Chat::NyoyMcpConfig.method(:configured?)
    begin
      Chat::NyoyMcpConfig.define_singleton_method(:configured?) { |account: nil| true }

      post refine_image_generation_agent_chat_url(42),
        params: { draft_index: 9 },
        as: :json

      assert_response :unprocessable_entity
      assert_includes JSON.parse(response.body)["error"], "draft_index"
    ensure
      Chat::NyoyMcpConfig.define_singleton_method(:configured?, original_configured)
    end
  end

  test "create interprets natural language draft selection as refine request" do
    conversation = accounts(:one).agent_chat_conversations.create!
    conversation.messages.create!(
      role: "assistant",
      content: "ラフ案です",
      intent: "image_generation",
      model_role: "main",
      metadata: {
        "mcp" => {
          "image_urls" => [
            "https://nyoy.example/draft1.png",
            "https://nyoy.example/draft2.png"
          ],
          "image_generation_watch" => { "id" => 42, "status" => "awaiting_selection" }
        }
      }
    )

    calls = []
    client = Object.new
    client.define_singleton_method(:site_origin) { "https://nyoy.example" }
    client.define_singleton_method(:call_tool) do |name:, arguments:|
      calls << [ name.to_s, arguments ]
      case name.to_s
      when "refine_image"
        { "id" => arguments[:id] || arguments["id"] }
      when "get_image_generation"
        {
          "id" => arguments[:id] || arguments["id"],
          "status" => "completed",
          "image_url" => "/rails/active_storage/final.png",
          "show_path" => "/image_generations/#{arguments[:id] || arguments["id"]}"
        }
      else
        raise "unexpected tool #{name}"
      end
    end

    original_client = Chat::NyoyMcpConfig.method(:client)
    original_configured = Chat::NyoyMcpConfig.method(:configured?)
    original_new = Chat::Agent.method(:new)
    begin
      Chat::NyoyMcpConfig.define_singleton_method(:client) { |account: nil| client }
      Chat::NyoyMcpConfig.define_singleton_method(:configured?) { |account: nil| true }
      Chat::Agent.define_singleton_method(:new) { |**_kwargs| raise "Chat::Agent should not be called" }

      post agent_chat_url,
        params: {
          conversation_id: conversation.id,
          messages: [ { role: "user", content: "2番を選んで" } ]
        },
        as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "image_generation", body["intent"]
      assert_equal "nyoy_mcp", body["model_role"]
      assert_equal "completed", body.dig("mcp", "image_generation_watch", "status")
      assert_equal [
        [ "refine_image", { id: 42, draft_index: 1 } ],
        [ "get_image_generation", { id: 42 } ]
      ], calls

      messages = conversation.reload.messages.ordered.to_a
      assert_equal "2番を選んで", messages[-2].content
      assert_equal "2番の仕上げを開始しました。", messages[-1].content
      assert_includes messages[-1].metadata.dig("mcp", "image_urls"), "https://nyoy.example/rails/active_storage/final.png"
    ensure
      Chat::NyoyMcpConfig.define_singleton_method(:client, original_client)
      Chat::NyoyMcpConfig.define_singleton_method(:configured?, original_configured)
      Chat::Agent.define_singleton_method(:new, original_new)
    end
  end

  test "create returns agent reply json" do
    fake_result = Chat::Agent::Result.new(
      reply: "回答です",
      intent: "rag_lookup",
      classification: nil,
      model_role: :main,
      escalated: false,
      tools: [ :rag_search ],
      pending_tools: false,
      rag: Chat::Tools::RagSearch::Result.new(
        queries: [ "q" ],
        hits: [],
        context_text: "",
        semantic_used: false
      )
    )

    original_new = Chat::Agent.method(:new)
    begin
      Chat::Agent.define_singleton_method(:new) { |**_kwargs| Object.new.tap { |o| o.define_singleton_method(:call) { |**_| fake_result } } }

      post agent_chat_url,
        params: { messages: [ { role: "user", content: "メモを探して" } ] },
        as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "回答です", body["reply"]
      assert_equal "rag_lookup", body["intent"]
      assert_equal "main", body["model_role"]
      assert_equal false, body["escalated"]
      assert_equal 0, body.dig("rag", "hit_count")
      assert_predicate body["conversation_id"], :present?

      conversation = AgentChatConversation.find(body["conversation_id"])
      assert_equal 2, conversation.messages.count
      assert_equal "メモを探して", conversation.messages.ordered.first.content
    ensure
      Chat::Agent.define_singleton_method(:new, original_new)
    end
  end

  test "create passes enabled_mcp_tools to agent" do
    captured = {}
    fake_result = Chat::Agent::Result.new(
      reply: "ok",
      intent: "conversation",
      classification: nil,
      model_role: :fast_chat,
      escalated: false,
      tools: [],
      pending_tools: false,
      rag: nil
    )

    original_new = Chat::Agent.method(:new)
    begin
      Chat::Agent.define_singleton_method(:new) do |**_kwargs|
        Object.new.tap do |o|
          o.define_singleton_method(:call) do |**kwargs|
            captured.replace(kwargs)
            fake_result
          end
        end
      end

      post agent_chat_url,
        params: {
          messages: [ { role: "user", content: "hi" } ],
          enabled_mcp_tools: [ "web_search", "fetch_url" ]
        },
        as: :json

      assert_response :success
      assert_equal [ "web_search", "fetch_url" ], captured[:enabled_mcp_tools]
    ensure
      Chat::Agent.define_singleton_method(:new, original_new)
    end
  end

    test "create passes attachments from top-level params to agent" do
      ulid = "01JABCDEFGHJKMNPQRSTVWXYZ0"
      captured = {}
      fake_result = Chat::Agent::Result.new(
        reply: "ok",
        intent: "image_analysis",
        classification: nil,
        model_role: :main,
        escalated: false,
        tools: [],
        pending_tools: false,
        rag: nil
      )

      original_new = Chat::Agent.method(:new)
      begin
        Chat::Agent.define_singleton_method(:new) do |**_kwargs|
          Object.new.tap do |o|
            o.define_singleton_method(:call) do |**kwargs|
              captured.replace(kwargs)
              fake_result
            end
          end
        end

        post agent_chat_url,
          params: {
            messages: [ { role: "user", content: "この写真は？" } ],
            attachments: [ { tsuzura_media_id: ulid, filename: "photo.jpg" } ]
          },
          as: :json

        assert_response :success
        assert_equal [ { tsuzura_media_id: ulid, filename: "photo.jpg" } ], captured[:image_attachments]
      ensure
        Chat::Agent.define_singleton_method(:new, original_new)
      end
    end

    test "create passes attachments embedded in last user message" do
      ulid = "01JABCDEFGHJKMNPQRSTVWXYZ0"
      captured = {}
      fake_result = Chat::Agent::Result.new(
        reply: "ok",
        intent: "image_analysis",
        classification: nil,
        model_role: :main,
        escalated: false,
        tools: [],
        pending_tools: false,
        rag: nil
      )

      original_new = Chat::Agent.method(:new)
      begin
        Chat::Agent.define_singleton_method(:new) do |**_kwargs|
          Object.new.tap do |o|
            o.define_singleton_method(:call) do |**kwargs|
              captured.replace(kwargs)
              fake_result
            end
          end
        end

        post agent_chat_url,
          params: {
            messages: [
              {
                role: "user",
                content: "この写真は？",
                attachments: [ { tsuzura_media_id: ulid, filename: "photo.jpg" } ]
              }
            ]
          },
          as: :json

        assert_response :success
        assert_equal [ { tsuzura_media_id: ulid, filename: "photo.jpg" } ], captured[:image_attachments]
      ensure
        Chat::Agent.define_singleton_method(:new, original_new)
      end
    end

    test "create returns error when reply blank" do
    fake_result = Chat::Agent::Result.new(
      reply: nil, intent: "unknown", classification: nil,
      model_role: nil, escalated: false, tools: [], pending_tools: false, rag: nil
    )

    original_new = Chat::Agent.method(:new)
    begin
      Chat::Agent.define_singleton_method(:new) { |**_kwargs| Object.new.tap { |o| o.define_singleton_method(:call) { |**_| fake_result } } }

      post agent_chat_url, params: { messages: [ { role: "user", content: "?" } ] }, as: :json

      assert_response :unprocessable_entity
      assert_includes JSON.parse(response.body)["error"], "応答"
    ensure
      Chat::Agent.define_singleton_method(:new, original_new)
    end
  end

  test "create returns llm error as json" do
    original_new = Chat::Agent.method(:new)
    begin
      Chat::Agent.define_singleton_method(:new) do |**_kwargs|
        Object.new.tap do |o|
          o.define_singleton_method(:call) { |**_| raise Chat::LlmClient::Error, "down" }
        end
      end

      post agent_chat_url, params: { messages: [ { role: "user", content: "hi" } ] }, as: :json

      assert_response :unprocessable_entity
      assert_equal "down", JSON.parse(response.body)["error"]
    ensure
      Chat::Agent.define_singleton_method(:new, original_new)
    end
  end

  test "destroy clears persisted conversation" do
    conversation = accounts(:one).agent_chat_conversations.create!
    conversation.messages.create!(role: "user", content: "残す", metadata: {})

    assert_difference -> { AgentChatConversation.count }, -1 do
      delete agent_chat_url, params: { conversation_id: conversation.id }
    end

    assert_response :no_content
  end
end
