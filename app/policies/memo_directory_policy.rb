# frozen_string_literal: true

class MemoDirectoryPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def create?
    user.present?
  end

  def update?
    return false unless user
    return false if record.directory_list_readonly?

    return true if user.admin?

    user_editable_directory_path?
  end

  def destroy?
    return false unless user
    return false unless record.deletable?

    return true if user.admin?

    user_editable_directory_path?
  end

  private

  def user_editable_directory_path?
    uid = user.id
    MemoDirectory::PROTECTED_BUCKET_PATHS.any? do |bucket|
      base = "#{bucket}/u-#{uid}"
      record.full_path == base || record.full_path.start_with?("#{base}/")
    end
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
