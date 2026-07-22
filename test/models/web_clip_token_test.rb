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
require "test_helper"

class WebClipTokenTest < ActiveSupport::TestCase
  test "issuing a token does not invalidate existing tokens" do
    account = accounts(:one)
    first, first_raw = WebClipToken.issue!(account: account, name: "  Chrome  ")
    second, second_raw = WebClipToken.issue!(account: account, name: "Firefox")

    assert_equal "Chrome", first.name
    assert_equal first, WebClipToken.authenticate(first_raw)
    assert_equal second, WebClipToken.authenticate(second_raw)
    assert_equal 2, account.web_clip_tokens.count
  end

  test "destroying one token leaves the other token active" do
    account = accounts(:one)
    first, first_raw = WebClipToken.issue!(account: account)
    second, second_raw = WebClipToken.issue!(account: account)

    first.destroy!

    assert_nil WebClipToken.authenticate(first_raw)
    assert_equal second, WebClipToken.authenticate(second_raw)
  end
end
