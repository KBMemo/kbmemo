# frozen_string_literal: true

class NotebookPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    owner? || guest_visible_record?
  end

  def create?
    user.present?
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  alias publish? update?
  alias unpublish? update?
  alias available_memos? update?
  alias manage_memos? update?

  private

  def owner?
    user.present? && record.account_id == user.id
  end

  def guest_visible_record?
    record.guest_visible?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      guest = scope.guest_visible
      return guest unless user

      scope.where(account_id: user.id).or(guest)
    end
  end
end
