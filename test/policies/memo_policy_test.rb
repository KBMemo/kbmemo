# frozen_string_literal: true

require "test_helper"

class MemoPolicyTest < ActiveSupport::TestCase
  test "guest scope resolves only public_everyone memos" do
    pub = memos(:one)
    other = memos(:two)
    pub.update_columns(visibility: Memo.visibilities[:public_everyone])
    other.update_columns(visibility: Memo.visibilities[:owner_read_write])

    scope = MemoPolicy::Scope.new(nil, Memo.all).resolve
    assert_includes scope, pub
    assert_not_includes scope, other
  end

  test "guest may show public memo only" do
    m = memos(:one)
    m.update_columns(visibility: Memo.visibilities[:public_everyone])
    assert MemoPolicy.new(nil, m).show?

    m.update_columns(visibility: Memo.visibilities[:owner_read_write])
    assert_not MemoPolicy.new(nil, m).show?
  end

  test "owner sees private memo" do
    m = memos(:one)
    m.update_columns(visibility: Memo.visibilities[:owner_read_write])
    assert MemoPolicy.new(accounts(:one), m).show?
    assert_not MemoPolicy.new(accounts(:two), m).show?
  end

  test "group member sees group_read memo" do
    m = memos(:one)
    m.update!(visibility: :group_read, memo_group_id: memo_groups(:alpha).id, account: accounts(:one))
    assert MemoPolicy.new(accounts(:two), m).show?
  end

  test "group co-member can update group_read_write but not group_read" do
    m = memos(:one)
    m.update!(visibility: :group_read_write, memo_group_id: memo_groups(:alpha).id, account: accounts(:one))
    assert MemoPolicy.new(accounts(:two), m).update?

    m.update!(visibility: :group_read)
    assert_not MemoPolicy.new(accounts(:two), m).update?
    assert MemoPolicy.new(accounts(:one), m).update?
  end

  test "owner can update private memo" do
    m = memos(:one)
    m.update_columns(visibility: Memo.visibilities[:owner_read_write])
    assert MemoPolicy.new(accounts(:one), m).update?
    assert_not MemoPolicy.new(accounts(:two), m).update?
  end

  test "only owner can destroy" do
    m = memos(:one)
    m.update!(visibility: :group_read_write, memo_group_id: memo_groups(:alpha).id, account: accounts(:one))
    assert MemoPolicy.new(accounts(:one), m).destroy?
    assert_not MemoPolicy.new(accounts(:two), m).destroy?
  end

  test "system space memo can only be updated by admin" do
    m = memos(:one)
    m.update!(memo_directory: memo_directories(:system_docs))

    assert MemoPolicy.new(accounts(:one), m).update?
    assert_not MemoPolicy.new(accounts(:two), m).update?
  end

  test "admin can destroy system space memo" do
    m = memos(:one)
    m.update!(memo_directory: memo_directories(:system_docs))

    assert MemoPolicy.new(accounts(:one), m).destroy?
    assert_not MemoPolicy.new(accounts(:two), m).destroy?
  end

  test "docs_sync read-only memo cannot be updated or destroyed by owner" do
    m = memos(:one)
    m.update!(
      properties: {
        "docs_sync" => {
          "source_path" => "architecture/sample.adoc",
          "read_only" => true
        }
      }
    )

    policy = MemoPolicy.new(accounts(:one), m)
    assert policy.show?
    assert_not policy.update?
    assert_not policy.destroy?
  end
end
