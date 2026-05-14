# frozen_string_literal: true

class MemoDirectoryPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def create?
    user.present?
  end

  def update?
    user.present?
  end

  def destroy?
    user.present? && record.deletable?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if user.admin?

      uid = user.id
      bases = [ "", "home", "share", "public", "home/u-#{uid}", "share/u-#{uid}", "public/u-#{uid}" ]
      scope.where(full_path: bases)
        .or(scope.where("memo_directories.full_path LIKE ?", "home/u-#{uid}/%"))
        .or(scope.where("memo_directories.full_path LIKE ?", "share/u-#{uid}/%"))
        .or(scope.where("memo_directories.full_path LIKE ?", "public/u-#{uid}/%"))
    end
  end
end
