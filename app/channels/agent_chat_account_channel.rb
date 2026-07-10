# frozen_string_literal: true

# ログイン中アカウント向け AI チャット進行イベント（conversation_id / turn_id でフィルタ）。
class AgentChatAccountChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_account
  end
end
