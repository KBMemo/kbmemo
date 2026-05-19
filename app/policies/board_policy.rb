# frozen_string_literal: true

class BoardPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    owner?
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

  alias move_card? update?
  alias available_memos? show?

  private

  def owner?
    user.present? && record.account_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      scope.where(account_id: user.id)
    end
  end
end
