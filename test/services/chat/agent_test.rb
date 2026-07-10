# frozen_string_literal: true

require "test_helper"

module Chat
  class AgentTest < ActiveSupport::TestCase
    # 役割ごとに固定応答を返すスタブ。呼ばれた役割を記録する。
    class StubFactory
      attr_reader :calls

      def initialize(replies)
        @replies = replies
        @calls = []
      end

      def call(role)
        @calls << role
        StubClient.new(@replies.fetch(role, "reply(#{role})"))
      end
    end

    class StubClient
      def initialize(reply)
        @reply = reply
      end

      def chat(_messages, stream: false, **_opts, &block)
        block&.call({ content: @reply, thinking: "" })
        @reply
      end
    end

    class StubClassifier
      def initialize(result)
        @result = result
      end

      def classify(_text, account: nil, stream: false, &block)
        block&.call({ content: @result.intent, thinking: "" }) if stream
        @result
      end
    end

    def intent(name, confidence: 0.9)
      Chat::IntentClassifier::Result.new(
        intent: name, confidence: confidence, needs_tool: false, reason: ""
      )
    end

    def agent(intent_result, replies: {})
      factory = StubFactory.new(replies)
      [ Chat::Agent.new(classifier: StubClassifier.new(intent_result), client_factory: factory), factory ]
    end

    test "conversation stays on fast_chat" do
      a, factory = agent(intent("conversation"), replies: { fast_chat: "hi" })
      result = a.call(messages: [ { role: "user", content: "やあ" } ])

      assert_equal "hi", result.reply
      assert_equal :fast_chat, result.model_role
      refute result.escalated
      assert_equal [ :fast_chat ], factory.calls
    end

    test "intent is the name string and classification holds detail" do
      a, = agent(intent("conversation", confidence: 0.95), replies: { fast_chat: "hi" })
      result = a.call(messages: [ { role: "user", content: "やあ" } ])

      assert_equal "conversation", result.intent
      assert_in_delta 0.95, result.classification.confidence
    end

    test "empty history does not call the LLM" do
      a, factory = agent(intent("conversation"), replies: { fast_chat: "hi" })
      result = a.call(messages: [])

      assert_nil result.reply
      assert_nil result.model_role
      refute result.escalated
      assert_empty factory.calls
    end

    test "history without user turns does not call the LLM" do
      a, factory = agent(intent("conversation"), replies: { fast_chat: "hi" })
      result = a.call(messages: [ { role: "assistant", content: "先の返答" } ])

      assert_nil result.reply
      assert_empty factory.calls
    end

    test "code intent routes straight to main (no escalation needed)" do
      a, factory = agent(intent("code"), replies: { main: "final" })
      result = a.call(messages: [ { role: "user", content: "直して" } ])

      assert_equal "final", result.reply
      assert_equal :main, result.model_role
      refute result.escalated
      assert_equal [ :main ], factory.calls
    end

    test "low confidence conversation does not escalate when main matches fast_chat" do
      a, factory = agent(intent("conversation", confidence: 0.4), replies: { fast_chat: "d", main: "f" })
      result = a.call(messages: [ { role: "user", content: "?" } ], account: accounts(:one))

      refute result.escalated
      assert_equal [ :fast_chat ], factory.calls
    end

    test "non-chat role (image_generation) falls back to main and reports pending tools" do
      a, factory = agent(intent("image_generation"), replies: { main: "img-note" })
      result = a.call(messages: [ { role: "user", content: "猫の絵を描いて" } ])

      assert_equal :main, result.model_role
      assert result.pending_tools
      assert_includes result.tools, :image_generation
      assert_equal [ :main ], factory.calls
    end

    test "web_research delegates to nyoy mcp and clears pending tools" do
      client = Object.new
      client.define_singleton_method(:configured?) { true }
      client.define_singleton_method(:call_tool) do |name:, arguments:|
        { "results" => [{ "title" => "News" }] }
      end
      mcp_runner = Chat::Tools::NyoyMcpRunner.new(client: client)

      factory = RecordingFactory.new
      a = Chat::Agent.new(
        classifier: StubClassifier.new(intent("web_research")),
        client_factory: factory,
        mcp_runner: mcp_runner
      )
      result = a.call(messages: [ { role: "user", content: "最新の llama.cpp" } ])

      refute result.pending_tools
      assert_equal [ :web_search ], result.mcp.tools_run
      assert_equal [ :fetch_url ], result.mcp.tools_skipped
      system = system_content(factory.seen[:main])
      assert_includes system, "外部ツール結果（Nyoy MCP）"
      assert_includes system, "web_search"
    end

    test "url_analysis with mcp fetch_url clears pending when url present" do
      mcp_result = Chat::Tools::NyoyMcpRunner::Result.new(
        tools_run: [ :fetch_url ],
        tools_skipped: [],
        context_text: "### Nyoy MCP: fetch_url\n{}",
        errors: []
      )
      mcp_runner = Object.new
      mcp_runner.define_singleton_method(:configured?) { true }
      mcp_runner.define_singleton_method(:optional_skip?) { |tool, user_text:| tool == :fetch_url && user_text.include?("example.com") == false }
      mcp_runner.define_singleton_method(:call) { |**| mcp_result }

      factory = RecordingFactory.new
      a = Chat::Agent.new(
        classifier: StubClassifier.new(intent("url_analysis")),
        client_factory: factory,
        mcp_runner: mcp_runner
      )
      result = a.call(messages: [ { role: "user", content: "https://example.com を要約" } ])

      refute result.pending_tools
      assert_equal [ :fetch_url ], result.mcp.tools_run
    end

    # 役割ごとに渡された messages を記録するファクトリ。
    class RecordingFactory
      attr_reader :seen

      def initialize
        @seen = {}
      end

      def call(role)
        seen = @seen
        client = Object.new
        client.define_singleton_method(:chat) do |messages, **_opts|
          seen[role] = messages
          "reply(#{role})"
        end
        client
      end
    end

    def system_content(messages)
      first = messages.first
      first && first[:role] == "system" ? first[:content] : nil
    end

    test "injects fast_chat default prompt for conversation" do
      factory = RecordingFactory.new
      a = Chat::Agent.new(classifier: StubClassifier.new(intent("conversation")), client_factory: factory)
      a.call(messages: [ { role: "user", content: "やあ" } ])

      assert_equal Chat::Prompts::FAST_CHAT, system_content(factory.seen[:fast_chat])
    end

    test "injects CODING prompt for code intent" do
      factory = RecordingFactory.new
      a = Chat::Agent.new(classifier: StubClassifier.new(intent("code")), client_factory: factory)
      a.call(messages: [ { role: "user", content: "直して" } ])

      assert_equal Chat::Prompts::CODING, system_content(factory.seen[:main])
    end

    test "escalation uses main prompt when top role is heavier than fast_chat" do
      original = Chat::ModelRegistry.method(:for)
      main_cfg = Chat::ModelRegistry::Config.new(
        role: :main, provider: :llama_cpp, base_url: "http://heavy:10012",
        model: "gemma-4-12b", temperature: 0.5, api_key: nil
      )
      fast_cfg = Chat::ModelRegistry::Config.new(
        role: :fast_chat, provider: :llama_cpp, base_url: "http://fast:10011",
        model: "gemma-4-e4b", temperature: 0.4, api_key: nil
      )
      Chat::ModelRegistry.define_singleton_method(:for) do |role, account: nil|
        case role.to_sym
        when :main then main_cfg
        when :fast_chat then fast_cfg
        else original.call(role, account: account)
        end
      end

      factory = RecordingFactory.new
      a = Chat::Agent.new(
        classifier: StubClassifier.new(intent("conversation", confidence: 0.4)),
        client_factory: factory
      )
      a.call(messages: [ { role: "user", content: "?" } ])

      assert_equal Chat::Prompts::FAST_CHAT, system_content(factory.seen[:fast_chat])
      assert_equal Chat::Prompts::MAIN, system_content(factory.seen[:main])
    ensure
      Chat::ModelRegistry.define_singleton_method(:for, original)
      Chat::ModelRegistry.reset!
    end

    test "rag_lookup with account runs rag and injects RAG_ANSWER" do
      stub_rag = Object.new
      stub_rag.define_singleton_method(:call) do |user_text:|
        Chat::Tools::RagSearch::Result.new(
          queries: [ "q" ],
          hits: [
            Chat::Tools::RagSearch::Hit.new(memo_id: 1, title: "T", excerpt: "body text")
          ],
          context_text: "### 資料 1: T\nmemo_id: 1\nbody text"
        )
      end

      factory = RecordingFactory.new
      a = Chat::Agent.new(
        classifier: StubClassifier.new(intent("rag_lookup")),
        client_factory: factory,
        rag_search: stub_rag
      )
      result = a.call(
        messages: [ { role: "user", content: "メモを探して" } ],
        account: accounts(:one)
      )

      refute result.pending_tools
      assert result.rag
      system = system_content(factory.seen[:main])
      assert_includes system, Chat::Prompts::RAG_ANSWER
      assert_includes system, "body text"
    end

    test "rag_lookup without account does not inject search context" do
      factory = RecordingFactory.new
      a = Chat::Agent.new(
        classifier: StubClassifier.new(intent("rag_lookup")),
        client_factory: factory
      )
      a.call(messages: [ { role: "user", content: "メモを探して" } ])

      assert_equal Chat::Prompts::MAIN, system_content(factory.seen[:main])
    end

    test "prepends system prompt when given" do
      captured = nil
      factory = Object.new
      factory.define_singleton_method(:call) do |_role|
        client = Object.new
        client.define_singleton_method(:chat) do |messages, **_opts|
          captured = messages
          "ok"
        end
        client
      end
      a = Chat::Agent.new(classifier: StubClassifier.new(intent("conversation")), client_factory: factory)
      a.call(messages: [ { role: "user", content: "hi" } ], system_prompt: "SYS")

      assert_equal "system", captured.first[:role]
      assert_equal "SYS", captured.first[:content]
    end
  end
end
