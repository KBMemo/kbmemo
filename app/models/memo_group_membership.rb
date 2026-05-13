# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_group_memberships
#
#  id            :integer          not null, primary key
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :integer          not null
#  memo_group_id :integer          not null
#
# Indexes
#
#  index_memo_group_memberships_on_account_id                    (account_id)
#  index_memo_group_memberships_on_memo_group_id                 (memo_group_id)
#  index_memo_group_memberships_on_memo_group_id_and_account_id  (memo_group_id,account_id) UNIQUE
#
# Foreign Keys
#
#  account_id     (account_id => accounts.id)
#  memo_group_id  (memo_group_id => memo_groups.id)
#
class MemoGroupMembership < ApplicationRecord
  belongs_to :memo_group
  belongs_to :account

  validates :account_id, uniqueness: { scope: :memo_group_id }
end
