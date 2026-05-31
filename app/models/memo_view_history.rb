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
class MemoViewHistory < ApplicationRecord
  MAX_PER_ACCOUNT = 50

  HistoryList = Data.define(:memos, :viewed_at_by_memo_id)

  belongs_to :account
  belongs_to :memo

  validates :viewed_at, presence: true
  validates :view_sequence, presence: true
  validates :memo_id, uniqueness: { scope: :account_id }

  # 表示履歴: クリックしたメモだけ先頭へ移動し、他メモの相対順は変えない。
  # view_sequence にアカウント内で単調増加の値を付与する（先頭行と swap しない）。
  def self.record!(account:, memo:)
    return unless account && memo&.persisted?

    transaction do
      account_id = account.id
      # PostgreSQL は集約 + FOR UPDATE を許可しないため、行ロックと MAX 取得を分ける。
      where(account_id: account_id).lock.load
      next_seq = where(account_id: account_id).maximum(:view_sequence).to_i + 1
      entry = where(account_id: account_id).lock.find_or_initialize_by(memo_id: memo.id)
      entry.viewed_at = Time.current
      entry.view_sequence = next_seq
      entry.save!
      trim_old_entries(account_id)
    end
  end

  def self.recent_memos_for(account, scope:)
    recent_history(account, scope: scope).memos
  end

  def self.recent_history(account, scope:)
    empty = HistoryList.new(memos: scope.none, viewed_at_by_memo_id: {})
    return empty unless account

    rows = where(account_id: account.id)
      .order(view_sequence: :desc)
      .limit(MAX_PER_ACCOUNT)
      .pluck(:memo_id, :viewed_at)
    return empty if rows.empty?

    memo_ids = rows.map(&:first)
    viewed_at_by_memo_id = rows.to_h
    memos = scope.where(id: memo_ids).in_order_of(:id, memo_ids)
    HistoryList.new(memos: memos, viewed_at_by_memo_id: viewed_at_by_memo_id)
  end

  def self.trim_old_entries(account_id)
    ids_to_keep = where(account_id: account_id).order(view_sequence: :desc).limit(MAX_PER_ACCOUNT).pluck(:id)
    where(account_id: account_id).where.not(id: ids_to_keep).delete_all
  end
end
