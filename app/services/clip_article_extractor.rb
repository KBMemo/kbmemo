# frozen_string_literal: true

class ClipArticleExtractor
  REMOVE_SELECTORS = %w[
    script style noscript template nav header footer aside form dialog
  ].freeze
  CONTENT_SELECTORS = [ "article", "main", "[role='main']" ].freeze

  class << self
    def extract(html)
      document = Nokogiri::HTML.parse(html.to_s)
      document.css(REMOVE_SELECTORS.join(",")).each(&:remove)

      candidates = CONTENT_SELECTORS.flat_map { |selector| document.css(selector).to_a }.uniq
      content = candidates.max_by { |node| normalized_text(node).length }
      content ||= document.at_css("body")
      return "" unless content

      remove_hidden_content!(content)
      content.to_html.strip
    end

    private

    def normalized_text(node)
      node.text.to_s.gsub(/\s+/, " ").strip
    end

    def remove_hidden_content!(node)
      node.css("[hidden], [aria-hidden='true']").each(&:remove)
    end
  end
end
