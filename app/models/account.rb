# == Schema Information
#
# Table name: accounts
#
#  id                            :bigint           not null, primary key
#  admin                         :boolean          default(FALSE), not null
#  api_token_created_at          :datetime
#  api_token_digest              :string
#  api_token_prefix              :string
#  chat_server_settings          :jsonb            not null
#  email                         :string           not null
#  google_calendar_meta          :json             not null
#  google_calendar_refresh_token :text
#  nickname                      :string
#  nyoy_mcp_api_token            :text
#  nyoy_mcp_url                  :string
#  openai_api_key                :text
#  password_hash                 :string
#  status                        :integer          default("unverified"), not null
#  theme_preference              :json             not null
#  tsuzura_api_token_created_at  :datetime
#  tsuzura_api_token_digest      :string
#  tsuzura_api_token_prefix      :string
#
# Indexes
#
#  index_accounts_on_api_token_digest          (api_token_digest) UNIQUE
#  index_accounts_on_email                     (email) UNIQUE WHERE (status = ANY (ARRAY[1, 2]))
#  index_accounts_on_tsuzura_api_token_digest  (tsuzura_api_token_digest) UNIQUE
#
class Account < ApplicationRecord
  include Rodauth::Rails.model
  include EncryptedAttributeSafety
  include AccountThemePreference
  include AccountChatServerSettings
  include AccountNyoyMcpSettings
  include AccountGoogleCalendar
  enum :status, { unverified: 1, verified: 2, closed: 3 }

  encrypts :openai_api_key

  validates :nickname, length: { maximum: 40 }, allow_blank: true

  before_validation :normalize_nickname

  has_many :memos, dependent: :restrict_with_exception
  has_many :memo_templates, dependent: :destroy
  has_many :memo_group_memberships, dependent: :destroy
  has_many :memo_groups, through: :memo_group_memberships
  has_many :agent_chat_conversations, dependent: :destroy
  has_many :web_clip_tokens, dependent: :destroy

  after_create_commit :provision_memo_directory_user_space

  def openai_api_key_configured?
    encrypted_ciphertext_present?(:openai_api_key)
  end

  def openai_api_key_decryptable?
    encrypted_attribute_decryptable?(:openai_api_key)
  end

  def api_token_configured?
    api_token_digest.present?
  end

  def generate_api_token!
    raw = "kbmemo_#{SecureRandom.urlsafe_base64(32)}"
    update!(
      api_token_digest: self.class.digest_token(raw),
      api_token_prefix: raw[0, 16],
      api_token_created_at: Time.current
    )
    raw
  end

  def revoke_api_token!
    update!(
      api_token_digest: nil,
      api_token_prefix: nil,
      api_token_created_at: nil
    )
  end

  def self.find_by_api_token(token)
    digest = digest_token(token)
    return nil if digest.blank?

    find_by(api_token_digest: digest)
  end

  def self.digest_token(token)
    value = token.to_s.strip
    Digest::SHA256.hexdigest(value) if value.present?
  end

  def tsuzura_api_token_configured?
    tsuzura_api_token_digest.present?
  end

  def generate_tsuzura_api_token!
    raw = "tsuzura_#{SecureRandom.urlsafe_base64(32)}"
    update!(
      tsuzura_api_token_digest: self.class.digest_tsuzura_api_token(raw),
      tsuzura_api_token_prefix: raw[0, 16],
      tsuzura_api_token_created_at: Time.current
    )
    raw
  end

  def revoke_tsuzura_api_token!
    update!(
      tsuzura_api_token_digest: nil,
      tsuzura_api_token_prefix: nil,
      tsuzura_api_token_created_at: nil
    )
  end

  def self.find_by_tsuzura_api_token(token)
    digest = digest_tsuzura_api_token(token)
    return nil if digest.blank?

    find_by(tsuzura_api_token_digest: digest)
  end

  def self.digest_tsuzura_api_token(token)
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
