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
      strip_github_clip_artifacts!(fragment)
      strip_presentation_attributes!(fragment)
      fragment.to_html.strip
    end

    private

    def unwrap_blockquotes!(fragment)
      fragment.css("blockquote").each do |blockquote|
        blockquote.replace(blockquote.inner_html)
      end
    end

    def strip_github_clip_artifacts!(fragment)
      fragment.css("svg").each(&:remove)

      fragment.css("a").each do |anchor|
        anchor.remove if decorative_heading_anchor?(anchor)
      end
    end

    def decorative_heading_anchor?(anchor)
      href = anchor["href"].to_s.strip
      return false unless href.start_with?("#")

      children = anchor.element_children
      return true if children.empty? && anchor.text.to_s.strip.blank?
      return true if children.any? && children.all? { |node| node.name == "svg" }

      false
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
