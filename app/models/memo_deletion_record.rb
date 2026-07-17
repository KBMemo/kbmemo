# frozen_string_literal: true

# Tombstone-like record used by the export/deletions API after Memo rows are physically deleted.
# == Schema Information
#
# Table name: memo_deletion_records
#
#  id         :bigint           not null, primary key
#  deleted_at :datetime         not null
#  memo_uid   :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  memo_id    :bigint           not null
#
# Indexes
#
#  idx_on_account_id_deleted_at_id_e0cd234d50              (account_id,deleted_at,id)
#  index_memo_deletion_records_on_account_id               (account_id)
#  index_memo_deletion_records_on_account_id_and_memo_uid  (account_id,memo_uid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class MemoDeletionRecord < ApplicationRecord
  belongs_to :account

  validates :memo_id, :memo_uid, :deleted_at, presence: true
  validates :memo_uid, format: { with: Memo::UID_FORMAT }
  validates :memo_uid, uniqueness: { scope: :account_id }
end
