# == Schema Information
#
# Table name: accounts
#
#  id            :integer          not null, primary key
#  admin         :boolean          default(FALSE), not null
#  email         :string           not null
#  password_hash :string
#  status        :integer          default("unverified"), not null
#
# Indexes
#
#  index_accounts_on_email  (email) UNIQUE WHERE status IN (1, 2)
#
class Account < ApplicationRecord
  include Rodauth::Rails.model
  enum :status, { unverified: 1, verified: 2, closed: 3 }

  has_many :memos, dependent: :restrict_with_exception
  has_many :memo_group_memberships, dependent: :destroy
  has_many :memo_groups, through: :memo_group_memberships

  after_create_commit :provision_memo_directory_user_space

  private

  def provision_memo_directory_user_space
    MemoDirectory::UserSpace.ensure_for_account!(self)
  end
end
