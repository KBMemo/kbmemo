# frozen_string_literal: true

require "digest/md5"

module AvatarsHelper
  # @param account [Account] メールは Gravatar の識別子に使う
  # @param pixel_size [Integer] Gravatar に要求する画像の辺ピクセル（最大 512）
  def gravatar_url_for(account, pixel_size: 120)
    return "" unless account

    email = account.email.to_s.strip.downcase
    return "" if email.blank?

    hash = Digest::MD5.hexdigest(email)
    s = pixel_size.to_i.clamp(1, 512)
    "https://secure.gravatar.com/avatar/#{hash}?s=#{s}&d=mp&r=g"
  end

  # @param size [Integer] 表示の一辺（px）
  def gravatar_image_tag(account, size: 32, extra_class: nil)
    return "".html_safe unless account

    label = account.display_name
    px = [[size.to_i * 2, 512].min, 1].max
    url = gravatar_url_for(account, pixel_size: px)
    return "".html_safe if url.blank?

    image_tag(
      url,
      alt: "#{label}のアバター",
      title: label,
      class: ["kb-avatar", extra_class].compact.join(" "),
      style: "width:#{size}px;height:#{size}px",
      loading: "lazy",
      decoding: "async"
    )
  end
end
