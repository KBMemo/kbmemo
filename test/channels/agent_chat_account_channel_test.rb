# frozen_string_literal: true

require "test_helper"

class AgentChatAccountChannelTest < ActionCable::Channel::TestCase
  tests AgentChatAccountChannel

  test "subscribes for current account" do
    stub_connection current_account: accounts(:one)
    subscribe

    assert subscription.confirmed?
    assert_has_stream_for accounts(:one)
  end
end
