# frozen_string_literal: true

require "test_helper"

class Tsuzura::AuthorizerTest < ActiveSupport::TestCase
  test "signs urls when memo is public" do
    memo = memos(:one)
    memo.update!(visibility: :public_everyone)
    authorizer = Tsuzura::Authorizer.new(memo: memo, viewer: nil)
    ulid = ULID.generate.to_s

    assert authorizer.allowed?
    assert authorizer.sign_media_url(ulid).include?(ulid)
  end

  test "denies private memo for other account" do
    memo = memos(:two)
    viewer = accounts(:one)
    authorizer = Tsuzura::Authorizer.new(memo: memo, viewer: viewer)

    assert_not authorizer.allowed?
    assert_nil authorizer.sign_media_url(ULID.generate.to_s)
  end
end
