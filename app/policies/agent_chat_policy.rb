# frozen_string_literal: true

# 独立 AI チャット画面（Chat::Agent）の認可。ログイン済みアカウントのみ。
class AgentChatPolicy < ApplicationPolicy
  def show?
    user.present?
  end

  alias create? show?
  alias destroy? show?
  alias nyoy_tools? show?
  alias memo_references? show?
  alias update_memo_references? show?
  alias memo_images? show?
  alias upload_memo_image? show?
  alias upload_image? show?
  alias synthesize_audio? show?
  alias image_generation_status? show?
  alias refine_image_generation? show?
end
