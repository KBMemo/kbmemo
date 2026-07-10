# frozen_string_literal: true

# == Schema Information
#
# Table name: accounts
#
#  id                            :bigint           not null, primary key
#  admin                         :boolean          default(FALSE), not null
#  chat_server_settings          :jsonb            not null
#  clip_api_token_created_at     :datetime
#  clip_api_token_digest         :string
#  clip_api_token_prefix         :string
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
#  index_accounts_on_clip_api_token_digest     (clip_api_token_digest) UNIQUE
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
end
