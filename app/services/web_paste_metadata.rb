# frozen_string_literal: true

# Extract clip/paste metadata from HTML fragments (mirrors webPasteHtmlMetadata.js).
class WebPasteMetadata
  KBMEMO_COMMENT_RE = /<!--\s*kbmemo:([\s\S]*?)\s*-->/i

  Metadata = Data.define(:url, :title)

  class << self
    def extract(html, url: nil, title: nil)
      from_html = extract_from_html(html.to_s)
      Metadata.new(
        url: normalize_string(url) || from_html&.url,
        title: normalize_string(title) || from_html&.title
      )
    end

    def strip_kbmemo_comment(html)
      html.to_s.gsub(KBMEMO_COMMENT_RE, "").strip
    end

    private

    def extract_from_html(html)
      trimmed = html.to_s.strip
      return nil if trimmed.blank?

      from_comment = extract_kbmemo_comment_metadata(trimmed)
      from_blockquote = extract_blockquote_cite(trimmed)

      url = from_comment&.url || from_blockquote&.url
      title = from_comment&.title
      return nil if url.blank? && title.blank?

      Metadata.new(url:, title:)
    end

    def extract_kbmemo_comment_metadata(html)
      match = html.match(KBMEMO_COMMENT_RE)
      return nil unless match

      parsed = JSON.parse(match[1])
      return nil unless parsed.is_a?(Hash)

      url = normalize_string(parsed["url"] || parsed[:url])
      title = normalize_string(parsed["title"] || parsed[:title])
      return nil if url.blank? && title.blank?

      Metadata.new(url:, title:)
    rescue JSON::ParserError
      nil
    end

    def extract_blockquote_cite(html)
      doc = Nokogiri::HTML.fragment(html)
      cite = doc.at_css("blockquote[cite]")&.[]("cite")&.strip
      return nil if cite.blank?

      Metadata.new(url: cite, title: nil)
    end

    def normalize_string(value)
      str = value.to_s.strip
      str.presence
    end
  end
end
