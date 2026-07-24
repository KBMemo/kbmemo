# frozen_string_literal: true

class MemoTemplatePolicy < ApplicationPolicy
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
