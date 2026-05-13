# frozen_string_literal: true

class TagPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def update?
    user.present?
  end

  def destroy?
    user.present?
  end

  def merge_form?
    user.present?
  end

  def merge?
    user.present?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      user ? scope.all : scope.none
    end
  end
end
