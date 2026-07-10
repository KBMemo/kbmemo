# frozen_string_literal: true

# アカウント別 Nyoy MCP 接続設定。ログイン済みアカウントのみ。
class NyoyMcpSettingsPolicy < ApplicationPolicy
  def show?
    user.present?
  end

  alias update? show?
  alias test_connection? show?
end
