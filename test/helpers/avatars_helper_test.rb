# frozen_string_literal: true

require "test_helper"

class AvatarsHelperTest < ActionView::TestCase
  include AvatarsHelper

  test "gravatar_url_for embeds md5 of normalized email" do
    account = accounts(:one)
    hash = Digest::MD5.hexdigest(account.email.downcase.strip)
    url = gravatar_url_for(account, pixel_size: 80)
    assert_includes url, hash
    assert_includes url, "s=80"
    assert_includes url, "secure.gravatar.com"
  end

  test "gravatar_image_tag returns empty when account nil" do
    assert_equal "", gravatar_image_tag(nil).to_s
  end
end
