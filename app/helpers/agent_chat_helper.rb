# frozen_string_literal: true

module AgentChatHelper
  PENDING_TOOL_LABELS = {
    "web_search" => "Web 検索",
    "fetch_url" => "URL 取得",
    "image_generation" => "画像生成",
    "image_analysis" => "画像解析",
    "memo_add" => "メモ作成"
  }.freeze

  def agent_chat_conversation_list_time(time)
    time.in_time_zone.strftime("%-m月%-d日 %H:%M")
  end

  def agent_chat_pending_tool_label(tool_name)
    PENDING_TOOL_LABELS.fetch(tool_name.to_s, tool_name.to_s)
  end
end
