# frozen_string_literal: true

# ブックマークレット由来の HTML を AsciiDoc 変換前に整える。
class ClipHtmlPreparer
  PRESENTATION_ATTRS = %w[class id style].freeze

  class << self
    def prepare(html)
      trimmed = WebPasteMetadata.strip_kbmemo_comment(html.to_s.strip)
      return "" if trimmed.blank?

      fragment = Nokogiri::HTML.fragment(trimmed)
      unwrap_blockquotes!(fragment)
      strip_presentation_attributes!(fragment)
      fragment.to_html.strip
    end

    private

    def unwrap_blockquotes!(fragment)
      fragment.css("blockquote").each do |blockquote|
        blockquote.replace(blockquote.inner_html)
      end
    end

    def strip_presentation_attributes!(fragment)
      fragment.traverse do |node|
        next unless node.element?

        node.attribute_nodes.each do |attr|
          name = attr.name
          next unless PRESENTATION_ATTRS.include?(name) || name.start_with?("data-")

          node.remove_attribute(name)
        end
      end
    end
  end
end
