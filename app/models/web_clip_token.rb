# frozen_string_literal: true

# == Schema Information
#
# Table name: web_clip_tokens
#
#  id           :bigint           not null, primary key
#  name         :string
#  token_digest :string           not null
#  token_prefix :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#
# Indexes
#
#  index_web_clip_tokens_on_account_id    (account_id)
#  index_web_clip_tokens_on_token_digest  (token_digest) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class WebClipToken < ApplicationRecord
  belongs_to :account

  validates :name, length: { maximum: 80 }, allow_blank: true
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true

  before_validation :normalize_name

  def self.issue!(account:, name: nil)
    raw = "kbmemo_clip_#{SecureRandom.urlsafe_base64(32)}"
    token = account.web_clip_tokens.create!(
      name: name,
      token_digest: digest(raw),
      token_prefix: raw[0, 20]
    )
    [ token, raw ]
  end

  def self.authenticate(raw)
    token_digest = digest(raw)
    return if token_digest.blank?

    includes(:account).find_by(token_digest: token_digest)
  end

  def self.digest(raw)
    value = raw.to_s.strip
    Digest::SHA256.hexdigest(value) if value.present?
  end

  private

  def normalize_name
    self.name = name.to_s.strip.presence
  end
end
