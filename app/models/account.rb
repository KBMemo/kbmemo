# == Schema Information
#
# Table name: accounts
#
#  id             :integer          not null, primary key
#  admin          :boolean          default(FALSE), not null
#  email          :string           not null
#  nickname       :string
#  openai_api_key :text
#  password_hash  :string
#  status         :integer          default("unverified"), not null
#
# Indexes
#
#  index_accounts_on_email  (email) UNIQUE WHERE status IN (1, 2)
#
class Account < ApplicationRecord
  include Rodauth::Rails.model
  enum :status, { unverified: 1, verified: 2, closed: 3 }

  encrypts :openai_api_key

  validates :nickname, length: { maximum: 40 }, allow_blank: true

  before_validation :normalize_nickname

  has_many :memos, dependent: :restrict_with_exception
  has_many :memo_group_memberships, dependent: :destroy
  has_many :memo_groups, through: :memo_group_memberships

  after_create_commit :provision_memo_directory_user_space

  def openai_api_key_configured?
    openai_api_key.present?
  end

  # 画面表示用。未設定ならメールアドレスをそのまま使う。
  def display_name
    nick = nickname.to_s.strip
    nick.presence || email.to_s
  end

  private

  def normalize_nickname
    self.nickname = nickname.to_s.strip.presence
  end

  def provision_memo_directory_user_space
    MemoDirectory::UserSpace.ensure_for_account!(self)
  end
end
