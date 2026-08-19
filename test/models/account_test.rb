# frozen_string_literal: true

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
require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "display_name uses nickname when present" do
    a = accounts(:one)
    assert_equal "Freddie", a.display_name
  end

  test "display_name falls back to email when nickname blank" do
    a = accounts(:two)
    assert_equal "brian@queen.com", a.display_name
  end

  test "nickname is stripped and blank becomes nil" do
    a = accounts(:two)
    a.update!(nickname: "  Brian  ")
    assert_equal "Brian", a.nickname
    a.update!(nickname: "   ")
    assert_nil a.nickname
  end

  test "nickname length validation" do
    a = accounts(:two)
    a.nickname = "x" * 41
    assert_not a.valid?
    assert_includes a.errors[:nickname], "is too long (maximum is 40 characters)"
  end

  test "account and web clip tokens are independent" do
    account = accounts(:one)
    api_token = account.generate_api_token!
    record, web_clip_token = WebClipToken.issue!(account: account)

    assert api_token.start_with?("kbmemo_")
    assert web_clip_token.start_with?("kbmemo_clip_")
    assert_equal account, Account.find_by_api_token(api_token)
    assert_equal record, WebClipToken.authenticate(web_clip_token)
    assert_nil Account.find_by_api_token(web_clip_token)
    assert_nil WebClipToken.authenticate(api_token)
  end

  test "openai_api_key_configured? survives undecryptable ciphertext" do
    account = accounts(:one)
    corrupt_encrypted_attribute!(account, :openai_api_key, "sk-test")

    assert_raises(ActiveRecord::Encryption::Errors::Base) { account.openai_api_key }
    assert account.openai_api_key_configured?
    assert_not account.openai_api_key_decryptable?
  end

  test "google_calendar_connected? is false when refresh token cannot be decrypted" do
    account = accounts(:one)
    account.connect_google_calendar!(refresh_token: "refresh-test")
    corrupt_encrypted_attribute!(account, :google_calendar_refresh_token)

    assert account.google_calendar_refresh_token_undecryptable?
    assert_not account.google_calendar_connected?
  end

  test "connect_google_calendar! overwrites an undecryptable refresh token" do
    account = accounts(:one)
    account.connect_google_calendar!(refresh_token: "old-token")
    corrupt_encrypted_attribute!(account, :google_calendar_refresh_token)

    account.connect_google_calendar!(refresh_token: "new-token")

    assert_equal "new-token", account.google_calendar_refresh_token
    assert account.google_calendar_connected?
  end

  test "connect_google_calendar! succeeds when another encrypted attribute is undecryptable" do
    account = accounts(:one)
    corrupt_encrypted_attribute!(account, :openai_api_key, "sk-test")

    account.connect_google_calendar!(refresh_token: "new-token")

    assert_equal "new-token", account.google_calendar_refresh_token
    assert account.openai_api_key_configured?
    assert_not account.openai_api_key_decryptable?
  end

  test "disconnect_google_calendar! succeeds when refresh token is undecryptable" do
    account = accounts(:one)
    account.connect_google_calendar!(refresh_token: "old-token")
    corrupt_encrypted_attribute!(account, :google_calendar_refresh_token)

    account.disconnect_google_calendar!

    assert_not account.google_calendar_connected?
    assert_not account.google_calendar_refresh_token_undecryptable?
  end

  test "openai_api_key can be replaced when existing ciphertext is undecryptable" do
    account = accounts(:one)
    corrupt_encrypted_attribute!(account, :openai_api_key, "sk-old")

    account.update!(openai_api_key: "sk-new")

    assert_equal "sk-new", account.openai_api_key
  end
end
