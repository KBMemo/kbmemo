# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_view_histories
#
#  id            :bigint           not null, primary key
#  view_sequence :bigint           not null
#  viewed_at     :datetime         not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :integer          not null
#  memo_id       :integer          not null
#
# Indexes
#
#  index_memo_view_histories_on_account_id                    (account_id)
#  index_memo_view_histories_on_account_id_and_memo_id        (account_id,memo_id) UNIQUE
#  index_memo_view_histories_on_account_id_and_view_sequence  (account_id,view_sequence DESC)
#  index_memo_view_histories_on_account_id_and_viewed_at      (account_id,viewed_at)
#  index_memo_view_histories_on_memo_id                       (memo_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (memo_id => memos.id)
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

  test "record! keeps all history entries without a max per account" do
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

    assert_equal 3, MemoViewHistory.where(account_id: @account.id).count
    assert MemoViewHistory.exists?(account: @account, memo: @one)
  end

  test "recent_memos_for returns memos in viewed_at order" do
    MemoViewHistory.record!(account: @account, memo: @one)
    travel 1.minute do
      MemoViewHistory.record!(account: @account, memo: @two)
    end

    scope = Memo.where(id: [ @one.id, @two.id ])
    recent = MemoViewHistory.recent_memos_for(@account, scope: scope)
    assert_equal [ @two, @one ], recent.to_a
  end

  test "recent_memos_for orders by view_sequence when viewed_at is identical" do
    freeze_time do
      MemoViewHistory.record!(account: @account, memo: @one)
      MemoViewHistory.record!(account: @account, memo: @two)
      MemoViewHistory.record!(account: @account, memo: @one)
    end

    one_entry = MemoViewHistory.find_by!(account: @account, memo: @one)
    two_entry = MemoViewHistory.find_by!(account: @account, memo: @two)
    assert_equal one_entry.viewed_at, two_entry.viewed_at
    assert_operator one_entry.view_sequence, :>, two_entry.view_sequence

    scope = Memo.where(id: [ @one.id, @two.id ])
    recent = MemoViewHistory.recent_memos_for(@account, scope: scope)
    assert_equal [ @one, @two ], recent.to_a
  end

  test "recent_history preserves relative order when reopening an older memo" do
    third = Memo.create!(
      title: "Third memo",
      body: "body",
      memo_directory: memo_directories(:work),
      account: @account,
      file_committed_at: Time.current
    )
    scope = Memo.where(id: [ @one.id, @two.id, third.id ])

    travel_to Time.zone.parse("2026-01-01 12:00:00") do
      MemoViewHistory.record!(account: @account, memo: @one)
      travel 1.minute
      MemoViewHistory.record!(account: @account, memo: @two)
      travel 1.minute
      MemoViewHistory.record!(account: @account, memo: third)
      travel 1.minute
      MemoViewHistory.record!(account: @account, memo: @one)

      recent = MemoViewHistory.recent_memos_for(@account, scope: scope)
      assert_equal [ @one, third, @two ], recent.to_a
    end
  end

  test "clicking C in A B C D history yields C A B D" do
    memo_c = Memo.create!(
      title: "Memo C",
      body: "body",
      memo_directory: memo_directories(:work),
      account: @account,
      file_committed_at: Time.current
    )
    memo_d = Memo.create!(
      title: "Memo D",
      body: "body",
      memo_directory: memo_directories(:work),
      account: @account,
      file_committed_at: Time.current
    )
    scope = Memo.where(id: [ @one.id, @two.id, memo_c.id, memo_d.id ])

    travel_to Time.zone.parse("2026-01-01 12:00:00") do
      MemoViewHistory.record!(account: @account, memo: memo_d)
      travel 1.minute
      MemoViewHistory.record!(account: @account, memo: memo_c)
      travel 1.minute
      MemoViewHistory.record!(account: @account, memo: @two)
      travel 1.minute
      MemoViewHistory.record!(account: @account, memo: @one)
      travel 1.minute
      MemoViewHistory.record!(account: @account, memo: memo_c)

      recent = MemoViewHistory.recent_memos_for(@account, scope: scope)
      assert_equal [ "Memo C", "First memo", "Second memo", "Memo D" ], recent.map(&:title)
    end
  end
end
