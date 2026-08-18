# frozen_string_literal: true

# 本番ダンプを development にリストアしたときなど、暗号化鍵が一致しないと
# `encrypts` 属性の読み取りが Decryption で落ちる。画面の「設定済み」判定は
# 暗号文の有無で行い、復号できるかは別メソッドで見る。
#
# 新しい値を書き込むときも、変更検知が古い暗号文を復号しようとして落ちる。
# 代入前に復号できない列を nil へ戻す。
module EncryptedAttributeSafety
  extend ActiveSupport::Concern

  def assign_attributes(new_attributes)
    forget_undecryptable_encrypted_attributes_for_assignment!(new_attributes)
    super
  end

  private

  def encrypted_ciphertext_present?(name)
    read_attribute_before_type_cast(name.to_s).present?
  end

  def encrypted_attribute_decryptable?(name)
    return false unless encrypted_ciphertext_present?(name)

    public_send(name)
    true
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  def forget_undecryptable_encrypted_attributes_for_assignment!(new_attributes)
    return unless persisted?
    return if new_attributes.blank?

    assigned = assignment_attribute_keys(new_attributes)
    Array(self.class.encrypted_attributes).each do |name|
      key = name.to_s
      next unless assigned.include?(key)
      next unless encrypted_ciphertext_present?(key)
      next if encrypted_attribute_decryptable?(key)

      forget_undecryptable_encrypted_attribute!(key)
    end
  end

  def forget_undecryptable_encrypted_attribute!(name)
    ActiveRecord::Encryption.without_encryption do
      update_column(name, nil)
    end
    @attributes.write_from_database(name.to_s, nil)
    clear_attribute_change(name)
  end

  def assignment_attribute_keys(new_attributes)
    hash =
      if new_attributes.respond_to?(:to_unsafe_h)
        new_attributes.to_unsafe_h
      else
        new_attributes.to_h
      end
    hash.stringify_keys.keys
  end
end
