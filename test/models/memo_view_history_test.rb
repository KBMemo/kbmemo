# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_view_histories
#
#  id         :integer          not null, primary key
#  viewed_at  :datetime         not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :integer          not null
#  memo_id    :integer          not null
#
# Indexes
#
#  index_memo_view_histories_on_account_id                (account_id)
#  index_memo_view_histories_on_account_id_and_memo_id    (account_id,memo_id) UNIQUE
#  index_memo_view_histories_on_account_id_and_viewed_at  (account_id,viewed_at)
#  index_memo_view_histories_on_memo_id                   (memo_id)
#
# Foreign Keys
#
#  account_id  (account_id => accounts.id)
#  memo_id     (memo_id => memos.id)
#
require "test_helper"

class MemoViewHistoryTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @one = memos(:one)
    @two = memos(:two)
    MemoViewHistory.delete_all
  end

  test "record! creates and updates viewed_at" do
    MemoViewHistory.record!(account: @account, memo: @one)
    entry = MemoViewHistory.find_by!(account: @account, memo: @one)

    travel 1.hour do
      MemoViewHistory.record!(account: @account, memo: @one)
      assert entry.reload.viewed_at > 1.hour.ago
    end
  end

  test "record! trims entries beyond max per account" do
    original_max = MemoViewHistory::MAX_PER_ACCOUNT
    MemoViewHistory.send(:remove_const, :MAX_PER_ACCOUNT)
    MemoViewHistory.const_set(:MAX_PER_ACCOUNT, 2)

    MemoViewHistory.record!(account: @account, memo: @one)
    MemoViewHistory.record!(account: @account, memo: @two)
    third = Memo.create!(
      title: "Third",
      body: "body",
      memo_directory: memo_directories(:work),
      account: @account,
      file_committed_at: Time.current
    )
    MemoViewHistory.record!(account: @account, memo: third)

    assert_equal 2, MemoViewHistory.where(account_id: @account.id).count
    assert_not MemoViewHistory.exists?(account: @account, memo: @one)
  ensure
    MemoViewHistory.send(:remove_const, :MAX_PER_ACCOUNT)
    MemoViewHistory.const_set(:MAX_PER_ACCOUNT, original_max)
  end

  test "recent_memos_for returns memos in viewed_at order" do
    MemoViewHistory.record!(account: @account, memo: @one)
    travel 1.minute do
      MemoViewHistory.record!(account: @account, memo: @two)
    end

    scope = Memo.where(id: [@one.id, @two.id])
    recent = MemoViewHistory.recent_memos_for(@account, scope: scope)
    assert_equal [@two, @one], recent.to_a
  end
end
