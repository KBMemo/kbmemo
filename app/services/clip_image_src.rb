# frozen_string_literal: true

require "cgi"
require "uri"

# クリップ HTML の <img> から取り込み用 URL とファイル名候補を解決する。
module ClipImageSrc
  IMG_SRC_ATTRS = %w[src data-src data-original data-lazy-src].freeze
  IMGIX_HOST_PATTERN = /\.imgix\.net\z/i

  module_function

  def effective_src(img)
    candidates = IMG_SRC_ATTRS.filter_map { |attr| normalize_attr(img[attr]) }
    candidates.concat(srcset_urls(img["srcset"]))
    candidates.find { |src| fetchable?(src) }
  end

  def canonical_fetch_url(src, base_url: nil)
    absolute = absolute_url(src, base_url: base_url)
    return nil if absolute.blank?

    unwrap_imgix_proxy(absolute)
  rescue URI::InvalidURIError
    nil
  end

  def filename_hint(img, fetch_url)
    alt = normalize_attr(img["alt"])
    if alt.present? && alt.match?(/\.(png|jpe?g|gif|webp|svg)\z/i)
      return MemoAssetFilename.sanitize(alt)
    end

    canonical = unwrap_imgix_proxy(fetch_url.to_s)
    path_name = filename_from_path(URI.parse(canonical).path)
    return path_name if path_name.present?

    filename_from_path(URI.parse(fetch_url.to_s).path)
  rescue URI::InvalidURIError
    nil
  end

  def normalize_attr(value)
    text = CGI.unescapeHTML(value.to_s.strip)
    text.presence
  end

  def fetchable?(src)
    src.present? && !src.match?(/\A(?:data|blob):/i)
  end

  def srcset_urls(srcset)
    srcset.to_s.split(",").filter_map do |part|
      url = part.strip.split(/\s+/, 2).first
      normalize_attr(url) if fetchable?(url)
    end
  end

  def absolute_url(src, base_url:)
    base = base_url.to_s.strip.presence || "about:blank"
    URI.join(base, src).to_s
  rescue URI::InvalidURIError
    nil
  end

  def unwrap_imgix_proxy(url)
    uri = URI.parse(url)
    return url unless uri.host.to_s.match?(IMGIX_HOST_PATTERN)

    embedded_path = uri.path.to_s.delete_prefix("/")
    return url if embedded_path.blank?

    decoded = CGI.unescape(embedded_path)
    return decoded if decoded.match?(/\Ahttps?:\/\//i)

    url
  rescue URI::InvalidURIError
    url
  end

  def filename_from_path(path)
    basename = File.basename(path.to_s)
    return nil if basename.blank?

    sanitized = MemoAssetFilename.sanitize(basename)
    sanitized == MemoAssetFilename::DEFAULT ? nil : sanitized
  end
end
