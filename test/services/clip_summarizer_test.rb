# frozen_string_literal: true

require "test_helper"

class ClipSummarizerTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:reply, :messages) do
    def chat(messages, temperature:)
      self.messages = messages
      reply
    end
  end

  FakeConfig = Struct.new(:client) do
    def build_client
      client
    end
  end

  test "summarizes extracted content with the fast chat model" do
    client = FakeClient.new("```asciidoc\n概要です。\n\n== 重要ポイント\n\n* 要点\n```")
    config = FakeConfig.new(client)

    Chat::ModelRegistry.stub(:for, config) do
      result = ClipSummarizer.call(account: accounts(:one), content: "本文")

      assert_equal "概要です。\n\n== 重要ポイント\n\n* 要点", result
      assert_equal "system", client.messages.first[:role]
      assert_equal "本文", client.messages.last[:content]
    end
  end

  test "limits content sent to the model" do
    client = FakeClient.new("要約")
    config = FakeConfig.new(client)

    Chat::ModelRegistry.stub(:for, config) do
      ClipSummarizer.call(
        account: accounts(:one),
        content: "x" * (ClipSummarizer::MAX_CONTENT_LENGTH + 100)
      )
    end

    assert_equal ClipSummarizer::MAX_CONTENT_LENGTH, client.messages.last[:content].length
  end
end
