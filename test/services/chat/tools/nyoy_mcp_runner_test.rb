# frozen_string_literal: true

require "test_helper"

module Chat
  module Tools
    class NyoyMcpRunnerTest < ActiveSupport::TestCase
      test "runs web_search with user text" do
        client = stub_client(
          "web_search" => { "results" => [ { "title" => "A" } ] }
        )
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call(tools: [ :web_search ], user_text: "最新の Ruby")

        assert_equal [ "web_search" ], result.tools_run
        assert_empty result.tools_skipped
        assert_includes result.context_text, "web_search"
        assert_includes result.context_text, "A"
      end

      test "runs mcp_names directly" do
        client = stub_client(
          "web_search" => { "results" => [] }
        )
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call(mcp_names: [ "web_search" ], user_text: "query")

        assert_equal [ "web_search" ], result.tools_run
      end

      test "skips fetch_url when user text has no url" do
        client = stub_client
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call(tools: [ :fetch_url ], user_text: "要約して")

        assert_empty result.tools_run
        assert_equal [ "fetch_url" ], result.tools_skipped
        assert runner.optional_skip?(:fetch_url, user_text: "要約して")
      end

      test "runs fetch_url when url is present" do
        client = stub_client(
          "fetch_url" => { "title" => "Example", "content_preview" => "body" }
        )
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call(
          tools: [ :fetch_url ],
          user_text: "https://example.com/docs を読んで"
        )

        assert_equal [ "fetch_url" ], result.tools_run
        assert_includes result.context_text, "Example"
      end

      test "chains search_fetched_page when fetch_url is truncated" do
        client = stub_client(
          "fetch_url" => {
            "title" => "Long page",
            "truncated" => true,
            "page_id" => "page-abc"
          },
          "search_fetched_page" => {
            "excerpts" => [ { "text" => "matched section" } ]
          }
        )
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call(
          tools: [ :fetch_url ],
          user_text: "https://example.com/long 価格について"
        )

        assert_equal [ "fetch_url", "search_fetched_page" ], result.tools_run
        assert_includes result.context_text, "matched section"
      end

      test "chains get_image_generation until completed" do
        calls = []
        client = Object.new
        client.define_singleton_method(:configured?) { true }
        client.define_singleton_method(:call_tool) do |name:, arguments:|
          calls << [ name.to_s, arguments ]
          case name.to_s
          when "generate_image"
            { "id" => 42 }
          when "get_image_generation"
            { "status" => "completed", "image_url" => "https://example.com/img.png" }
          else
            raise "unexpected tool #{name}"
          end
        end

        runner = NyoyMcpRunner.new(client: client)
        result = runner.call(tools: [ :image_generation ], user_text: "猫のイラスト")

        assert_equal [ "generate_image", "get_image_generation" ], result.tools_run
        assert_equal [ "get_image_generation", { id: 42 } ], calls.last
        assert_includes result.context_text, "completed"
        assert_equal [ "https://example.com/img.png" ], result.image_urls
      end

      test "captures nyoy show_path when generation awaits draft selection" do
        calls = []
        client = Object.new
        client.define_singleton_method(:configured?) { true }
        client.define_singleton_method(:site_origin) { "https://nyoy.example" }
        client.define_singleton_method(:call_tool) do |name:, arguments:|
          calls << name.to_s
          case name.to_s
          when "generate_image"
            { "id" => 42 }
          when "get_image_generation"
            {
              "status" => "awaiting_selection",
              "show_path" => "/image_generations/42",
              "draft_urls" => [ "https://nyoy.example/rails/active_storage/blobs/draft.png" ]
            }
          else
            raise "unexpected tool #{name}"
          end
        end

        runner = NyoyMcpRunner.new(client: client)
        result = runner.call(mcp_names: [ "generate_image" ], user_text: "猫のイラスト")

        assert_equal [ "generate_image", "get_image_generation" ], result.tools_run
        assert_equal [ "https://nyoy.example/rails/active_storage/blobs/draft.png" ], result.image_urls
        assert_equal({ id: 42, status: "awaiting_selection", show_url: "https://nyoy.example/image_generations/42" }, result.image_generation_watch)
      end

      test "sets image generation watch when generation is still in progress" do
        attempts = 0
        client = Object.new
        client.define_singleton_method(:configured?) { true }
        client.define_singleton_method(:site_origin) { "https://nyoy.example" }
        client.define_singleton_method(:call_tool) do |name:, arguments:|
          case name.to_s
          when "generate_image"
            { "id" => 9 }
          when "get_image_generation"
            attempts += 1
            { "id" => 9, "status" => "drafting" }
          else
            raise "unexpected tool #{name}"
          end
        end

        runner = NyoyMcpRunner.new(client: client)
        result = runner.call(mcp_names: [ "generate_image" ], user_text: "猫")

        assert_equal 1, attempts
        assert_equal({ id: 9, status: "drafting" }, result.image_generation_watch)
        assert_empty result.image_urls
      end

      test "records error when image generation failed" do
        client = Object.new
        client.define_singleton_method(:configured?) { true }
        client.define_singleton_method(:call_tool) do |name:, arguments:|
          case name.to_s
          when "generate_image"
            { "id" => 12 }
          when "get_image_generation"
            { "status" => "failed", "error_message" => "SD pipeline error" }
          else
            raise "unexpected tool #{name}"
          end
        end

        runner = NyoyMcpRunner.new(client: client)
        result = runner.call(mcp_names: [ "generate_image" ], user_text: "猫")

        assert_equal [ "generate_image", "get_image_generation" ], result.tools_run
        assert_equal "SD pipeline error", result.errors.first[:message]
        assert_nil result.image_generation_watch
      end

      test "sets image generation watch when first status check is still running" do
        client = Object.new
        client.define_singleton_method(:configured?) { true }
        client.define_singleton_method(:call_tool) do |name:, arguments:|
          case name.to_s
          when "generate_image"
            { "id" => 7 }
          when "get_image_generation"
            { "id" => 7, "status" => "running" }
          end
        end

        runner = NyoyMcpRunner.new(client: client)
        result = runner.call(mcp_names: [ "generate_image" ], user_text: "風景画")

        assert_equal [ "generate_image", "get_image_generation" ], result.tools_run
        assert_equal({ id: 7, status: "running" }, result.image_generation_watch)
        assert_empty result.image_urls
      end

      test "runs list_prompt_styles with empty arguments" do
        client = stub_client(
          "list_prompt_styles" => { "styles" => [ { "id" => "anime" } ] }
        )
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call(mcp_names: [ "list_prompt_styles" ], user_text: "スタイル一覧")

        assert_equal [ "list_prompt_styles" ], result.tools_run
        assert_includes result.context_text, "anime"
      end

      test "runs search_memos and recall_memos with query text" do
        client = stub_client(
          "search_memos" => { "memos" => [ { "title" => "Memo A" } ] },
          "recall_memos" => { "memos" => [ { "title" => "Recall B" } ] }
        )
        runner = NyoyMcpRunner.new(client: client)

        search = runner.call(mcp_names: [ "search_memos" ], user_text: "旅行")
        recall = runner.call(mcp_names: [ "recall_memos" ], user_text: "旅行")

        assert_equal [ "search_memos" ], search.tools_run
        assert_equal [ "recall_memos" ], recall.tools_run
      end

      test "runs get_media when ulid is present in user text" do
        ulid = "01JABCDEFGHJKMNPQRSTVWXYZ0"
        client = stub_client(
          "get_media" => { "id" => ulid, "title" => "Photo" }
        )
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call(
          mcp_names: [ "get_media" ],
          user_text: "この画像 #{ulid} を説明して"
        )

        assert_equal [ "get_media" ], result.tools_run
        assert_includes result.context_text, "Photo"
      end

      test "runs analyze_image with attached tsuzura media id" do
        ulid = "01JABCDEFGHJKMNPQRSTVWXYZ0"
        client = stub_client(
          "analyze_image" => { "description" => "A cat" }
        )
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call_planned(
          calls: [ { name: "analyze_image", arguments: { prompt: "何が写っている？" } } ],
          user_text: "何が写っている？",
          image_attachments: [ { tsuzura_media_id: ulid } ]
        )

      assert_equal [ "analyze_image" ], result.tools_run
      assert_includes result.context_text, "A cat"
    end

    test "call_planned builds analyze_image arguments when planner omits them" do
      ulid = "01JABCDEFGHJKMNPQRSTVWXYZ0"
      client = stub_client(
        "analyze_image" => { "description" => "A cat" }
      )
      runner = NyoyMcpRunner.new(client: client)

      result = runner.call_planned(
        calls: [ { name: "analyze_image", arguments: nil } ],
        user_text: "何が写っている？",
        image_attachments: [ { tsuzura_media_id: ulid } ]
      )

      assert_equal [ "analyze_image" ], result.tools_run
      assert_equal ulid, client.last_arguments["tsuzura_media_id"]
    end

    test "call_planned executes explicit arguments" do
        client = stub_client(
          "fetch_url" => { "title" => "Docs", "content_preview" => "hello" }
        )
        runner = NyoyMcpRunner.new(client: client)

        result = runner.call_planned(
          calls: [
            { name: "fetch_url", arguments: { url: "https://example.com/docs" } }
          ],
          user_text: "要約して"
        )

        assert_equal [ "fetch_url" ], result.tools_run
        assert_includes result.context_text, "Docs"
      end

      test "directly_invocable excludes chain-only and manual tools" do
        assert NyoyMcpRunner.directly_invocable?("web_search")
        assert NyoyMcpRunner.directly_invocable?("list_albums")
        assert NyoyMcpRunner.directly_invocable?("refine_image")
        refute NyoyMcpRunner.directly_invocable?("search_fetched_page")
        refute NyoyMcpRunner.directly_invocable?("create_memo")
      end

      test "records errors without raising" do
        client = Object.new
        client.define_singleton_method(:configured?) { true }
        client.define_singleton_method(:call_tool) { |**| raise Chat::NyoyMcpClient::ApiError, "down" }

        runner = NyoyMcpRunner.new(client: client)
        result = runner.call(tools: [ :web_search ], user_text: "q")

        assert_empty result.tools_run
        assert_equal [ "web_search" ], result.tools_skipped
        assert_equal "down", result.errors.first[:message]
      end

      private

      def stub_client(responses = {})
        captured = {}
        client = Object.new
        client.define_singleton_method(:configured?) { true }
        client.define_singleton_method(:call_tool) do |name:, arguments:|
          captured[:arguments] = arguments
          responses.fetch(name.to_s) { raise "unexpected tool #{name} (#{arguments.inspect})" }
        end
        client.define_singleton_method(:last_arguments) { captured[:arguments] }
        client
      end
    end
  end
end
