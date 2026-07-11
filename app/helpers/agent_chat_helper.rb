# frozen_string_literal: true

module AgentChatHelper
  def agent_chat_conversation_list_time(time)
    time.in_time_zone.strftime("%-m月%-d日 %H:%M")
  end
end
