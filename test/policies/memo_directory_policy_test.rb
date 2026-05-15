# frozen_string_literal: true

require "test_helper"

class MemoDirectoryPolicyTest < ActiveSupport::TestCase
  test "top level buckets are not updatable" do
    %i[home share public].each do |key|
      dir = memo_directories(key)
      assert dir.directory_list_readonly?
      assert_not MemoDirectoryPolicy.new(accounts(:one), dir).update?
      assert_not MemoDirectoryPolicy.new(accounts(:two), dir).update?
    end
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
end
