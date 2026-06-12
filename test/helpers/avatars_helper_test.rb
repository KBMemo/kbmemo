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

  test "gravatar_image_tag sets intrinsic dimensions" do
    html = gravatar_image_tag(accounts(:one), size: 28, extra_class: "shrink-0").to_s

    assert_includes html, 'width="28"'
    assert_includes html, 'height="28"'
    assert_not_includes html, "style="
    assert_includes html, 'loading="lazy"'
    assert_includes html, 'decoding="async"'
  end

  test "gravatar_image_tag allows priority for above the fold avatars" do
    html = gravatar_image_tag(accounts(:one), loading: "eager", fetchpriority: "low").to_s

    assert_includes html, 'loading="eager"'
    assert_includes html, 'fetchpriority="low"'
  end
end
