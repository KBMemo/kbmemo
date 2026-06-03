# frozen_string_literal: true

module ClipBookmarkletHelper
  API_TEMPLATE = Rails.root.join("public/bookmarklets/kbmemo_clip_api.bookmarklet.js").freeze
  CLIPBOARD_TEMPLATE = Rails.root.join("public/bookmarklets/kbmemo_clip.bookmarklet.js").freeze

  module_function

  def origin_from_base_url(base_url)
    URI.parse(base_url.to_s).origin
  rescue URI::InvalidURIError
    base_url.to_s.sub(%r{/\z}, "")
  end

  def api_bookmarklet_href(base_url, token)
    template = File.read(API_TEMPLATE)
    origin = origin_from_base_url(base_url)
    code = template
      .gsub("__KBMEMO_BASE__", origin.to_json)
      .gsub("__KBMEMO_TOKEN__", token.to_s.to_json)
      .strip
    "javascript:#{ERB::Util.url_encode(code)}"
  end

  def clipboard_bookmarklet_href
    code = File.read(CLIPBOARD_TEMPLATE).strip
    "javascript:#{ERB::Util.url_encode(code)}"
  end
end
