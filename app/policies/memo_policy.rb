# frozen_string_literal: true

# メモの参照・更新権限。公開範囲は Scope と各メソッドで判定する。
class MemoPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  alias wiki_completions? index?
  alias wiki_link_labels? wiki_completions?

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
    return false unless user
    return true if record.account_id == user.id
    return false unless record.group_read_write?
    return false if record.memo_group_id.blank?

    MemoGroupMembership.exists?(memo_group_id: record.memo_group_id, account_id: user.id)
  end

  # member route `draft` → verify_authorized は draft? を参照する
  alias draft? update?

  def upload_asset?
    update?
  end

  def show_asset?
    show?
  end

  def destroy?
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
