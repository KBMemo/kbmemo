# frozen_string_literal: true

# ローカル llama-server 接続設定。ログイン済みアカウントのみ。
class ChatServerPolicy < ApplicationPolicy
  def show?
    user.present?
  end

  alias update? show?
  alias model_options? show?
  alias health_check? show?
  alias list_models? show?
end
