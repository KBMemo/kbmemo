# frozen_string_literal: true

require "test_helper"

class MemoDirectoryPolicyTest < ActiveSupport::TestCase
  test "top level buckets are not updatable" do
    %i[home share public system].each do |key|
      dir = memo_directories(key)
      assert dir.directory_list_readonly?
      assert_not MemoDirectoryPolicy.new(accounts(:one), dir).update?
      assert_not MemoDirectoryPolicy.new(accounts(:two), dir).update?
    end
  end

  test "non-admin cannot update system docs subtree" do
    arch = MemoDirectory.create!(parent: memo_directories(:system_docs), path_segment: "policy-arch", label: "Arch")
    assert arch.under_system_space?
    assert_not MemoDirectoryPolicy.new(accounts(:two), arch).update?
  end

  test "admin can update system docs subtree" do
    arch = MemoDirectory.create!(parent: memo_directories(:system_docs), path_segment: "admin-arch", label: "Arch")
    assert MemoDirectoryPolicy.new(accounts(:one), arch).update?
  end

  test "scope includes system help for regular users" do
    scope = MemoDirectoryPolicy::Scope.new(accounts(:two), MemoDirectory.all).resolve
    assert_includes scope.map(&:full_path), "system/help"
    assert_includes scope.map(&:full_path), "system/docs"
  end

  test "user can update directories under own home user space" do
    work = memo_directories(:work)
    assert MemoDirectoryPolicy.new(accounts(:one), work).update?
    assert_not MemoDirectoryPolicy.new(accounts(:two), work).update?
  end

  test "admin can update directories outside own user space but not top level buckets" do
    work = memo_directories(:work)
    assert MemoDirectoryPolicy.new(accounts(:one), work).update?
    assert_not MemoDirectoryPolicy.new(accounts(:one), memo_directories(:home)).update?
  end

  test "destroy denied when subtree has memos or user lacks path access" do
    empty = MemoDirectory.create!(parent: memo_directories(:home_u_one), path_segment: "policy-empty", label: "Policy empty")
    assert MemoDirectoryPolicy.new(accounts(:one), empty).destroy?

    Memo.create!(
      account: accounts(:one),
      memo_directory: empty,
      title: "Block delete",
      slug: "block-delete-policy-test",
      body: "body"
    )
    assert_not MemoDirectoryPolicy.new(accounts(:one), empty).destroy?
    assert_not MemoDirectoryPolicy.new(accounts(:two), empty).destroy?
  end
end
