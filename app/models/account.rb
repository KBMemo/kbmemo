# == Schema Information
#
# Table name: accounts
#
#  id                        :bigint           not null, primary key
#  admin                     :boolean          default(FALSE), not null
#  clip_api_token_created_at :datetime
#  clip_api_token_digest     :string
#  clip_api_token_prefix     :string
#  email                     :string           not null
#  nickname                  :string
#  openai_api_key            :text
#  password_hash             :string
#  status                    :integer          default("unverified"), not null
#  theme_preference          :json             not null
#
# Indexes
#
#  index_accounts_on_clip_api_token_digest  (clip_api_token_digest) UNIQUE
#  index_accounts_on_email                  (email) UNIQUE WHERE (status = ANY (ARRAY[1, 2]))
#
class Account < ApplicationRecord
  include Rodauth::Rails.model
  include AccountThemePreference
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

  def clip_api_token_configured?
    clip_api_token_digest.present?
  end

  def generate_clip_api_token!
    raw = "kbmemo_#{SecureRandom.urlsafe_base64(32)}"
    update!(
      clip_api_token_digest: self.class.digest_clip_api_token(raw),
      clip_api_token_prefix: raw[0, 16],
      clip_api_token_created_at: Time.current
    )
    raw
  end

  def revoke_clip_api_token!
    update!(
      clip_api_token_digest: nil,
      clip_api_token_prefix: nil,
      clip_api_token_created_at: nil
    )
  end

  def self.find_by_clip_api_token(token)
    digest = digest_clip_api_token(token)
    return nil if digest.blank?

    find_by(clip_api_token_digest: digest)
  end

  def self.digest_clip_api_token(token)
    value = token.to_s.strip
    return nil if value.blank?

    Digest::SHA256.hexdigest(value)
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
