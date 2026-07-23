# frozen_string_literal: true

require "test_helper"

class MemoMetadataSuggesterTest < ActiveSupport::TestCase
  test "suggests a title and tags while including existing tags in the prompt" do
    captured = nil
    client = Object.new
    client.define_singleton_method(:chat) do |messages, response_format:|
      captured = { messages: messages, response_format: response_format }
      '{"title":"Railsメモの整理","tags":["Rails","AI","Rails"]}'
    end

    result = MemoMetadataSuggester.new(
      account: accounts(:one),
      title: "仮タイトル",
      body: "RailsでAI機能を実装する。",
      current_tags: [ "開発" ],
      existing_tags: [ "Rails", "Ruby" ],
      client: client
    ).call

    assert_equal "Railsメモの整理", result[:title]
    assert_equal [ "Rails", "AI" ], result[:tags]
    assert_equal({ "type" => "json_object" }, captured[:response_format])
    assert_includes captured[:messages].last[:content], "Rails, Ruby"
    assert_includes captured[:messages].last[:content], "開発"
  end

  test "accepts JSON wrapped in a code fence" do
    client = Object.new
    client.define_singleton_method(:chat) do |*, **|
      "```json\n{\"title\":\"候補\",\"tags\":[\"既存\"]}\n```"
    end

    result = MemoMetadataSuggester.new(
      account: accounts(:one), title: "", body: "本文", current_tags: [],
      existing_tags: [], client: client
    ).call

    assert_equal({ title: "候補", tags: [ "既存" ] }, result)
  end

  test "rejects an invalid response" do
    client = Object.new
    client.define_singleton_method(:chat) { |*, **| "not json" }

    assert_raises(Chat::LlmClient::Error) do
      MemoMetadataSuggester.new(
        account: accounts(:one), title: "", body: "本文", current_tags: [],
        existing_tags: [], client: client
      ).call
    end
  end
end
