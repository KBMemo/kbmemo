# frozen_string_literal: true

# BYOK（OpenAI API キー）を Active Record Encryption で保存する。
# 本番は bin/rails db:encryption:init で credentials に鍵を置くか、環境変数で指定する。
Rails.application.config.active_record.encryption.tap do |encryption|
  encryption.primary_key = ENV.fetch(
    "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
    Rails.application.credentials.dig(:active_record_encryption, :primary_key) ||
      (Rails.env.local? ? "dev_primary_key________________________" : nil)
  )
  encryption.deterministic_key = ENV.fetch(
    "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
    Rails.application.credentials.dig(:active_record_encryption, :deterministic_key) ||
      (Rails.env.local? ? "dev_deterministic_key__________________" : nil)
  )
  encryption.key_derivation_salt = ENV.fetch(
    "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT",
    Rails.application.credentials.dig(:active_record_encryption, :key_derivation_salt) ||
      (Rails.env.local? ? "dev_key_derivation_salt________________" : nil)
  )
end
