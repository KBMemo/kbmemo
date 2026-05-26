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
class MemoViewHistory < ApplicationRecord
  MAX_PER_ACCOUNT = 50

  belongs_to :account
  belongs_to :memo

  validates :viewed_at, presence: true
  validates :memo_id, uniqueness: { scope: :account_id }

  def self.record!(account:, memo:)
    return unless account && memo&.persisted?

    entry = find_or_initialize_by(account_id: account.id, memo_id: memo.id)
    entry.viewed_at = Time.current
    entry.save!
    trim_old_entries(account.id)
  end

  def self.recent_memos_for(account, scope:)
    return scope.none unless account

    scope
      .joins(:memo_view_histories)
      .where(memo_view_histories: { account_id: account.id })
      .order("memo_view_histories.viewed_at DESC")
      .limit(MAX_PER_ACCOUNT)
  end

  def self.trim_old_entries(account_id)
    ids_to_keep = where(account_id: account_id).order(viewed_at: :desc).limit(MAX_PER_ACCOUNT).pluck(:id)
    where(account_id: account_id).where.not(id: ids_to_keep).delete_all
  end
end
