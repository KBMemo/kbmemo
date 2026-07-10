# frozen_string_literal: true

# 独立 AI チャット画面（Chat::Agent）の認可。ログイン済みアカウントのみ。
class AgentChatPolicy < ApplicationPolicy
  def show?
    user.present?
  end

  alias create? show?
  alias destroy? show?
end
