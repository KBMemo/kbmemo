# frozen_string_literal: true

require "test_helper"

class AgentChatHelperTest < ActionView::TestCase
  include AgentChatHelper

  test "agent_chat_conversation_list_time uses japanese month day and 24h clock" do
    time = Time.zone.parse("2026-07-12 02:40:54")
    assert_equal "7月12日 02:40", agent_chat_conversation_list_time(time)
  end
end
