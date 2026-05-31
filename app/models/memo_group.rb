# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_groups
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class MemoGroup < ApplicationRecord
  has_many :memo_group_memberships, dependent: :destroy
  has_many :accounts, through: :memo_group_memberships
  has_many :memos, dependent: :nullify

  validates :name, presence: true

  scope :for_account, ->(account_id) {
    joins(:memo_group_memberships).where(memo_group_memberships: { account_id: account_id }).distinct
  }
end
