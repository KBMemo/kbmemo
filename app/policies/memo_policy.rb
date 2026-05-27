# frozen_string_literal: true

# メモの参照・更新権限。公開範囲は Scope と各メソッドで判定する。
class MemoPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  alias wiki_completions? index?

  def show?
    return true if record.public_everyone?
    return false unless user

    return true if record.account_id == user.id
    return false unless record.group_read? || record.group_read_write?
    return false if record.memo_group_id.blank?

    MemoGroupMembership.exists?(memo_group_id: record.memo_group_id, account_id: user.id)
  end

  def create?
    user.present?
  end

  def update?
    return false if record.docs_sync_read_only?
    return false if record.system_space_memo? && !user&.admin?
    return false unless user
    return true if record.account_id == user.id
    return false unless record.group_read_write?
    return false if record.memo_group_id.blank?

    MemoGroupMembership.exists?(memo_group_id: record.memo_group_id, account_id: user.id)
  end

  # ノートブックへの追加: 通常メモは update?、docs/ 同期（閲覧専用）は show? のみ。
  def add_to_notebook?
    return show? if record.docs_sync_read_only?

    update?
  end

  # member route `draft` → verify_authorized は draft? を参照する
  alias draft? update?
  alias commit? update?
  alias revert_draft? update?
  alias ai_chat? update?

  def upload_asset?
    update?
  end

  def show_asset?
    show?
  end

  alias show_diagram? show?
  alias edit_diagram? update?

  def destroy?
    return false if record.docs_sync_read_only?
    return true if record.system_space_memo? && user&.admin?

    user.present? && record.account_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      vis = Memo.visibilities
      public_v = vis[:public_everyone]
      group_vis = [ vis[:group_read], vis[:group_read_write] ]

      if user.nil?
        return scope.where(visibility: public_v)
      end

      uid = user.id
      member_group_ids = MemoGroupMembership.where(account_id: uid).select(:memo_group_id)

      scope.where(visibility: public_v)
        .or(scope.where(account_id: uid))
        .or(scope.where(visibility: group_vis).where(memo_group_id: member_group_ids))
    end
  end
end
