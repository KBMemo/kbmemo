# frozen_string_literal: true

require "test_helper"

class AgentChat::UiBroadcasterTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @conversation = @account.agent_chat_conversations.create!
    @turn_id = SecureRandom.uuid
    @broadcaster = AgentChat::UiBroadcaster.new(
      account: @account,
      conversation: @conversation,
      turn_id: @turn_id
    )
    @payloads = []
  end

  test "broadcasts interaction payload" do
    with_capture do
      @broadcaster.interaction(
        step_key: "generate",
        role: "request",
        model: "gemma-4-e4b",
        text: "[user] hello"
      )
    end

    assert_equal 1, @payloads.size
    assert_equal "interaction", @payloads.first[:type]
    assert_equal @turn_id, @payloads.first[:turn_id]
    assert_equal @conversation.id, @payloads.first[:conversation_id]
  end

  test "increments seq" do
    with_capture do
      @broadcaster.turn_started
      @broadcaster.assistant_delta(text: "hi", thinking: false)
    end

    assert_equal [ 1, 2 ], @payloads.map { |payload| payload[:seq] }
  end

  private

  def with_capture
    AgentChatAccountChannel.stub(:broadcast_to, ->(_account, payload) { @payloads << payload }) do
      yield
    end
  end
end
