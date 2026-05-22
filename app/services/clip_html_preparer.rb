# frozen_string_literal: true

# ブックマークレット由来の HTML を AsciiDoc 変換前に整える。
class ClipHtmlPreparer
  class << self
    def prepare(html)
      trimmed = WebPasteMetadata.strip_kbmemo_comment(html.to_s.strip)
      unwrap_blockquote(trimmed)
    end

    private

    def unwrap_blockquote(html)
      return "" if html.blank?

      fragment = Nokogiri::HTML.fragment(html)
      blockquotes = fragment.css("blockquote")
      return fragment.to_html if blockquotes.empty?

      blockquotes.each do |blockquote|
        blockquote.replace(blockquote.inner_html)
      end

      fragment.to_html.strip
    end
  end
end
